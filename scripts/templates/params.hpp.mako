<%!
import re
from templates import helper as th
%><%
    n=namespace
    N=n.upper()

    x=tags['$x']
    X=x.upper()
%>/*
 *
 * Copyright (C) 2023 Intel Corporation
 *
 * Part of the Unified-Runtime Project, under the Apache License v2.0 with LLVM Exceptions.
 * See LICENSE.TXT
 * SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
 *
 * @file ${name}.hpp
 *
 */
#ifndef ${X}_PARAMS_HPP
#define ${X}_PARAMS_HPP 1

#include "${x}_api.h"
#include <ostream>
#include <bitset>

<%def name="member(iname, itype, loop)">
    %if iname == "pNext":
        ${x}_params::serializeStruct(os, ${caller.body()});
    %elif th.type_traits.is_flags(itype):
        ${x}_params::serializeFlag<${th.type_traits.get_flag_type(itype)}>(os, ${caller.body()});
    %elif not loop and th.type_traits.is_pointer(itype):
        ${x}_params::serializePtr(os, ${caller.body()});
    %elif loop and th.type_traits.is_pointer_to_pointer(itype):
        ${x}_params::serializePtr(os, ${caller.body()});
    %elif th.type_traits.is_handle(itype):
        ${x}_params::serializePtr(os, ${caller.body()});
    %else:
        os << ${caller.body()};
    %endif
</%def>

<%def name="line(item, n, params, params_dict)">
    <%
        iname = th._get_param_name(n, tags, item)
        prefix = "p" if params else ""
        pname = prefix + iname
        itype = th._get_type_name(n, tags, obj, item)
        access = "->" if params else "."
        deref = "*" if params else ""
        typename = th.param_traits.typename(item)
        if typename is not None:
            typename_size = th.param_traits.typename_size(item)
            underlying_type = params_dict[typename]
    %>
    %if n != 0:
        os << ", ";
    %endif
    ## can't iterate over 'void *'...
    %if th.param_traits.is_range(item) and "void*" not in itype:
        os << ".${iname} = {";
        for (size_t i = ${th.param_traits.range_start(item)}; ${deref}(params${access}${pname}) != NULL && i < ${deref}params${access}${prefix + th.param_traits.range_end(item)}; ++i) {
            if (i != 0) {
                os << ", ";
            }
            <%call expr="member(iname, itype, True)">
                (${deref}(params${access}${pname}))[i]
            </%call>
        }
        os << "}";
    %elif typename is not None:
        os << ".${iname} = ";
        ${x}_params::serializeTagged(os, ${deref}(params${access}${pname}), ${deref}(params${access}${prefix}${typename}), ${deref}(params${access}${prefix}${typename_size}));
    %else:
        os << ".${iname} = ";
        <%call expr="member(iname, itype, False)">
            ${deref}(params${access}${pname})
        </%call>
    %endif
</%def>

namespace ${x}_params {
template <typename T> inline void serializePtr(std::ostream &os, T *ptr);
template <typename T> inline void serializeFlag(std::ostream &os, uint32_t flag);
template <typename T> inline void serializeTagged(std::ostream &os, const void *ptr, T value, size_t size);

%for spec in specs:
%for obj in spec['objects']:
## ENUM #######################################################################
%if re.match(r"enum", obj['type']):
    %if obj.get('typed_etors', False) is True:
    template <> inline void serializeTagged(std::ostream &os, const void *ptr, ${th.make_enum_name(n, tags, obj)} value, size_t size);
    %elif "structure_type" in obj['name']:
    inline void serializeStruct(std::ostream &os, const void *ptr);
    %endif
%endif


%if th.type_traits.is_flags(obj['name']):
    template<> inline void serializeFlag<${th.make_enum_name(n, tags, obj)}>(std::ostream &os, uint32_t flag);
%endif
%endfor # obj in spec['objects']
%endfor
} // namespace ${x}_params

%for spec in specs:
%for obj in spec['objects']:
## ENUM #######################################################################
%if re.match(r"enum", obj['type']):
    inline std::ostream &operator<<(std::ostream &os, enum ${th.make_enum_name(n, tags, obj)} value);
%elif re.match(r"struct|union", obj['type']):
    inline std::ostream &operator<<(std::ostream &os, const ${obj['type']} ${th.make_type_name(n, tags, obj)} params);
%endif
%endfor # obj in spec['objects']
%endfor

%for spec in specs:
%for obj in spec['objects']:
## ENUM #######################################################################
%if re.match(r"enum", obj['type']):
    %if "api_version" in obj['name']:
    inline std::ostream &operator<<(std::ostream &os, enum ${th.make_enum_name(n, tags, obj)} value) {
        os << UR_MAJOR_VERSION(value) << "." << UR_MINOR_VERSION(value);
        return os;
    }
    %else:
    inline std::ostream &operator<<(std::ostream &os, enum ${th.make_enum_name(n, tags, obj)} value) {
        switch (value) {
            %for n, item in enumerate(obj['etors']):
                <%
                ename = th.make_etor_name(n, tags, obj['name'], item['name'])
                %>
                case ${ename}:
                    os << "${ename}";
                    break;
            %endfor
                default:
                    os << "unknown enumerator";
                    break;
        }
        return os;
    }
    %endif
    %if obj.get('typed_etors', False) is True:
    namespace ${x}_params {
    template <>
    inline void serializeTagged(std::ostream &os, const void *ptr, ${th.make_enum_name(n, tags, obj)} value, size_t size) {
        if (ptr == NULL) {
            serializePtr(os, ptr);
            return;
        }

        switch (value) {
            %for n, item in enumerate(obj['etors']):
                <%
                ename = th.make_etor_name(n, tags, obj['name'], item['name'])
                vtype = th.etor_get_associated_type(n, tags, item)
                %>
                case ${ename}: {
                    %if th.value_traits.is_array(vtype):
                    <% atype = th.value_traits.get_array_name(vtype) %>
                    const ${atype} *tptr = (const ${atype} *)ptr;
                        %if "char" in atype: ## print char* arrays as simple NULL-terminated strings
                            serializePtr(os, tptr);
                        %else:
                            os << "{";
                            size_t nelems = size / sizeof(${atype});
                            for (size_t i = 0; i < nelems; ++i) {
                                if (i != 0) {
                                    os << ", ";
                                }
                                <%call expr="member(tptr, atype, True)">
                                    tptr[i]
                                </%call>
                            }
                            os << "}";
                        %endif
                    %else:
                    const ${vtype} *tptr = (const ${vtype} *)ptr;
                    if (sizeof(${vtype}) > size) {
                        os << "invalid size (is: " << size << ", expected: >=" << sizeof(${vtype}) << ")";
                        return;
                    }
                    os << (void *)(tptr) << " (";
                    <%call expr="member(tptr, vtype, False)">
                        *tptr
                    </%call>
                    os << ")";
                    %endif
                } break;
            %endfor
                default:
                    os << "unknown enumerator";
                    break;
        }
    }
    }
    %elif "structure_type" in obj['name']:
    namespace ${x}_params {
    inline void serializeStruct(std::ostream &os, const void *ptr) {
        if (ptr == NULL) {
            ${x}_params::serializePtr(os, ptr);
            return;
        }

        ## structure type enum value must be first
        enum ${th.make_enum_name(n, tags, obj)} *value = (enum ${th.make_enum_name(n, tags, obj)} *)ptr;
        switch (*value) {
            %for n, item in enumerate(obj['etors']):
                <%
                ename = th.make_etor_name(n, tags, obj['name'], item['name'])
                %>
                case ${ename}: {
                    const ${th.subt(n, tags, item['desc'])} *pstruct = (const ${th.subt(n, tags, item['desc'])} *)ptr;
                    ${x}_params::serializePtr(os, pstruct);
                } break;
            %endfor
                default:
                    os << "unknown enumerator";
                    break;
        }
    }
    } // namespace ${x}_params
    %endif
%if th.type_traits.is_flags(obj['name']):
namespace ${x}_params {

template<>
inline void serializeFlag<${th.make_enum_name(n, tags, obj)}>(std::ostream &os, uint32_t flag) {
    uint32_t val = flag;
    bool first = true;
    %for n, item in enumerate(obj['etors']):
        <%
        ename = th.make_etor_name(n, tags, obj['name'], item['name'])
        %>
        if ((val & ${ename}) == (uint32_t)${ename}) {
            ## toggle the bits to avoid printing overlapping values
            ## instead of e.g., FLAG_FOO | FLAG_BAR | FLAG_ALL, this will just
            ## print FLAG_FOO | FLAG_BAR (or just FLAG_ALL, depending on order).
            val ^= (uint32_t)${ename};
            if (!first) {
                os << " | ";
            } else {
                first = false;
            }
            os << ${ename};
        }
    %endfor
    if (val != 0) {
        std::bitset<32> bits(val);
        if (!first) {
            os << " | ";
        }
        os << "unknown bit flags " << bits;
    } else if (first) {
        os << "0";
    }
}
} // namespace ${x}_params
%endif
## STRUCT/UNION ###############################################################
%elif re.match(r"struct|union", obj['type']):
inline std::ostream &operator<<(std::ostream &os, const ${obj['type']} ${th.make_type_name(n, tags, obj)} params) {
    os << "(${obj['type']} ${th.make_type_name(n, tags, obj)}){";
    <%
        mlist = obj['members']
        params_dict = dict()
        for item in mlist:
            iname = th._get_param_name(n, tags, item)
            itype = th._get_type_name(n, tags, obj, item)
            params_dict[iname] = itype
    %>
    %for n, item in enumerate(mlist):
        ${line(item, n, False, params_dict)}
    %endfor
    os << "}";
    return os;
}
%endif
%endfor # obj in spec['objects']
%endfor

%for tbl in th.get_pfncbtables(specs, meta, n, tags):
%for obj in tbl['functions']:

inline std::ostream &operator<<(std::ostream &os, const struct ${th.make_pfncb_param_type(n, tags, obj)} *params) {
    <%
        params_dict = dict()
        for item in obj['params']:
            iname = th._get_param_name(n, tags, item)
            itype = th._get_type_name(n, tags, obj, item)
            params_dict[iname] = itype
    %>
    %for n, item in enumerate(obj['params']):
        ${line(item, n, True, params_dict)}
    %endfor
    return os;
}

%endfor
%endfor

namespace ${x}_params {
## This is needed to avoid dereferencing forward declared handles
// https://devblogs.microsoft.com/oldnewthing/20190710-00/?p=102678
template<typename, typename = void>
constexpr bool is_type_complete_v = false;
template<typename T>
constexpr bool is_type_complete_v<T, std::void_t<decltype(sizeof(T))>> = true;

template <typename T> inline void serializePtr(std::ostream &os, T *ptr) {
    if (ptr == nullptr) {
        os << "nullptr";
    } else if constexpr (std::is_pointer_v<T>) {
        os << (void *)(ptr) << " (";
        serializePtr(os, *ptr);
        os << ")";
    } else if constexpr (std::is_void_v<T> || !is_type_complete_v<T>) {
        os << (void *)ptr;
    } else if constexpr (std::is_same_v<std::remove_cv_t< T >, char>) {
        os << (void *)(ptr) << " (";
        os << ptr;
        os << ")";
    } else {
        os << (void *)(ptr) << " (";
        os << *ptr;
        os << ")";
    }
}

inline int serializeFunctionParams(std::ostream &os, uint32_t function, const void *params) {
    switch((enum ${x}_function_t)function) {
    %for tbl in th.get_pfncbtables(specs, meta, n, tags):
    %for obj in tbl['functions']:
        case ${th.make_func_etor(n, tags, obj)}: {
            os << (const struct ${th.make_pfncb_param_type(n, tags, obj)} *)params;
        } break;
    %endfor
    %endfor
        default: return -1;
    }
    return 0;
}
} // namespace ur_params

#endif /* ${X}_PARAMS_HPP */
