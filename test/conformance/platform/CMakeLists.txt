# Copyright (C) 2022 Intel Corporation
# Part of the Unified-Runtime Project, under the Apache License v2.0 with LLVM Exceptions.
# See LICENSE.TXT
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

add_conformance_test(platform
    urInit.cpp
    urPlatformGet.cpp
    urPlatformGetBackendOption.cpp
    urPlatformGetInfo.cpp
    urTearDown.cpp)
