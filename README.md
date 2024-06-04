# SPIR-V Tools-zig

This is a fork of SPIRV-Tools with the additional ability to build with zig.

## Overview

This fork aims to preserve as much of the original SPIRV-Tools repository functionality and build flow while also integrating well into other zig projects.

Existing build files are pregenerated into `generated-include/` or can be built by setting `-Dregenerate_headers` in the build script. This requires a python installation on the system.

