# MakeDL

This package simplify building C/C++ code in Julia.

# Installation

`]add https://github.com/longqian95/MakeDL.git`

Modify `deps/deps.jl` to setup building environment.

Run `MakeDL.test()` or `MakeDL.test_essential()` to check if working


# Usage

- `cbuild("/tmp/f1.cpp")` build "/tmp/f1.cpp" to dll and return "/tmp/f1.so" (or .dll in windows)
- `cbuild_exe("/tmp/f1.cpp")` build "/tmp/f1.cpp" to exe and return "/tmp/f1" (or .exe in windows)
- `cbuild(["f1.cpp","f2.cpp"])` build multiple files
- `cbuild(code="int inc(int i) {return i+1;}",compiler="gcc")` build a piece of code and return the dll path
- `cbuild("f1.cpp",libs=["x1","x2.lib","c:/x3.lib","c:/x4.dll"],compiler="cl")` link with x1.lib or libx1.lib or x1.dll or libx1.dll, x2.lib, c:/x3.lib, and the lib generated from c:/x4.dll. (need to install visual studio and set `DEFAULT_VC_ENV` in `deps/deps.jl`)
- `cbuild("f1.cpp",matlab=true)` build mex file (need to set `DEFAULT_MATLAB_ROOT` in `deps/deps.jl`)
- `cbuild("f1.cu",compiler="nvcc")` build with CUDA (need to install CUDA)
- `cbuild("f1.cpp",opencv=true)` link with OpenCV (need to set `DEFAULT_OPENCV_ROOT` in `deps/deps.jl`)
- `cbuild("f1.cpp",julia=true)` link with Julia for embedding Julia or building with PackageCompiler

Check help for more functions: `cfunc,run_cc,run_opencv,@CC_str,rw_define,@dynamic` 

Check code in `test()` for more usages.

# Reference

```julia
function cbuild(;
        files::VStr=Str[], #input files. NOTICE: input file type is determined by its ext
        code::Str="", #if code is not empty, write code into a temp file and compile
        output::Str="", #if no ext, automatically add it according to output_type. if empty, use the name of the first input file
        output_type::Str="dll", #maybe dll, exe, ptx, cpp
        include_path::VStr=Str[],
        libs::VStr=Str[],
        lib_path::VStr=Str[],
        lib_rpath::VStr=Str[], #only work for Linux
        rpath::Bool=false, #make all lib_path also in lib_rpath, only work for Linux
        rpath_current::Bool=false, #add '${ORIGIN}' to rpath ($ORIGIN means the runtime dir containing the building target)
        defines::VStr=Str[],
        options::VStr=Str[],
        link_options::VStr=Str[],
        export_names::VStr=Str[], #specify the exported symbols, not necessary for gcc/g++/clang 
        compiler::Str="", #can be g++,gcc,clang,cl,icl,nvcc. Linux default is g++; Windows default is cl
        vc_env::VStr=DEFAULT_VC_ENV,
        icl_env::VStr=DEFAULT_ICL_ENV,
        julia::Bool=false, #build with Julia
        cxxwrap::Bool=false, #build with CxxWrap.jl (not work for windows)
        matlab::Bool=false, #build mex for MATLAB
        matlab_root::Str=DEFAULT_MATLAB_ROOT,
        matlab_gpu=false, #use mex gpu lib, nvcc compiler is necessary if true
        opencv::Bool=false, #link to OpenCV
        opencv_root::Str=DEFAULT_OPENCV_ROOT,
        opencv_libs::VStr=copy(DEFAULT_OPENCV_LIBS),
        opencv_static::Bool=false, #static link to OpenCV, only work for Windows
        opencv_rpath::Bool=true, #make OpenCV libs in rpath, only work for Linux
        openmp::Bool=false,
        fast_math::Bool=false,
        crt_static::Bool=false,
        warn::Bool=true, #show warnings
        fatal_error::Bool=false, #stop at the first error if true, not work for cl
        debug::Bool=false,
        show_cmd::Bool=false, #show the real cmd sent to compiler
        depend_files::VStr=Str[], #only be used to check if rebuild or not
        force::Bool=false, #force rebuild
    ) #return the compiled dll or exe file path
```