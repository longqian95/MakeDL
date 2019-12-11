# MakeDL

This package simplify building C/C++ code in Julia.

# Installation

`]add https://github.com/longqian95/MakeDL.git`

# Usage

- `cbuild("/tmp/f1.cpp")` build "/tmp/f1.cpp" to dll and return "/tmp/f1.so" (or .dll in windows)
- `cbuild_exe("/tmp/f1.cpp")` build "/tmp/f1.cpp" to exe and return "/tmp/f1" (or .exe in windows)
- `cbuild(["f1.cpp","f2.cpp"])` build multiple files
- `cbuild(code="int inc(int i) {return i+1;}",compiler="gcc")` build a piece of code and return the dll path
- `cbuild("f1.cpp",libs=["x1","x2.lib","c:/x3.lib","c:/x4.dll"])` link with x1.lib or libx1.lib, x2.lib, c:/x3.lib, lib generated from x4.dll
- `cbuild("f1.cpp",matlab=true) build mex file
- `cbuild("f1.cu",compiler="nvcc") build by cuda
- `cbuild("f1.cpp",opencv=true,julia=true)` link with opencv and julia

