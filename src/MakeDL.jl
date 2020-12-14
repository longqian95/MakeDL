module MakeDL

using Test,Libdl

export cbuild,cbuild_exe,cfunc,run_cc,run_opencv,@CC_str,rw_define,@dynamic,@srpath_str

let
    dep_file1=joinpath(dirname(@__DIR__), "deps", "MakeDL_settings.jl")
    dep_file2=joinpath(dirname(dirname(@__DIR__)), "MakeDL_settings.jl")
    dep_sample=joinpath(dirname(@__DIR__), "deps", "sample_settings.jl")
    include_dependency(dep_file1)
    include_dependency(dep_file2)
    if isfile(dep_file1)
        include(dep_file1)
    elseif isfile(dep_file2)
        include(dep_file2)
    else
        __precompile__(false)
        print("""

            ------------------------------------
            NOTICE:

            Please copy '$dep_sample' to '$dep_file2' and modify related settings in the file to setup building environment.

            Every setting should have value. If no information, set to ""

            Run `MakeDL.test()` or `MakeDL.test_essential()` to check settings.
            ------------------------------------
            """)
    end
end

const PEXPORTS = joinpath(dirname(@__DIR__),"deps","pexports.exe")
if !isfile(PEXPORTS)
    #download("https://sourceforge.net/projects/mingw/files/MinGW/Extension/pexports/pexports-0.47/pexports-0.47-mingw32-bin.tar.xz")
end

const Str = String
const VStr = Vector{String}


#NOTICE: file name in cmd should not contain space, otherwise cannot run
function run_vc_cmd(env,cmd;show_cmd) #run visual c++ command
    logfile1=tempname();
    logfile2=tempname();
    fullcmd=`$env \> $logfile1 \& $cmd \> $logfile2`
    if show_cmd
        println(cmd)
    end
    try
        run(fullcmd)
    catch
        isfile(logfile1) && println(read(logfile1,String))
        isfile(logfile2) && println(read(logfile2,String))
        @error("error at $fullcmd")
    end
    safe_rm(logfile1)
    safe_rm(logfile2)
end

function run_gcc_cmd(cmd;show_cmd) #run gcc command
    if show_cmd
        println(cmd)
    end
    try
        run(`$cmd`)
    catch
        @error("error at $cmd")
    end
end

#push or append only unique items
function upush!(collection, items...)
    for i in items
        if !(i in collection)
            push!(collection,i)
        end
    end
end
uappend!(collection, collection2) = upush!(collection,collection2...)

function divpath(p)
    dir,name=splitdir(p)
    name,ext=splitext(name)
    return dir,name,ext
end

function safe_rm(f)
    if isfile(f)
        try
            rm(f)
        catch
        end
    end
end

##old version. extract version from version.hpp 
# function get_opencv_version(opencv_root::Str)
#     v,=rw_define(joinpath(opencv_root,"include","opencv2","core","version.hpp");
#         CV_VERSION_EPOCH=Any,CV_VERSION_MAJOR=Any,CV_VERSION_MINOR=Any,CV_VERSION_REVISION=Any)
#     if haskey(v,:CV_VERSION_EPOCH)
#         m=tryparse(Int,v[:CV_VERSION_EPOCH])
#         if m!=nothing && m==2
#             return VersionNumber(m,parse(Int,v[:CV_VERSION_MAJOR]),parse(Int,v[:CV_VERSION_MINOR]))
#         else
#             @error("Get opencv version error")
#         end
#     elseif haskey(v,:CV_VERSION_MAJOR)
#         m=tryparse(Int,v[:CV_VERSION_MAJOR])
#         if m!=nothing && m>=3
#             return VersionNumber(m,parse(Int,v[:CV_VERSION_MINOR]),parse(Int,v[:CV_VERSION_REVISION]))
#         else
#             @error("Get opencv version error")
#         end
#     else
#         @error("Get opencv version error")
#     end
# end

function get_opencv_version(opencv_root::Str)
    bin=joinpath(opencv_root,"bin","opencv_version")
    ver_str=readchomp(`$bin`)
    return VersionNumber(join(split(ver_str,".")[1:3],"."))
end


"""
    pkg_dir(name::Str)

Get the dir of package without loading it. Return `nothing` if not found.
"""
function pkg_dir(name::Str)
    id=Base.identify_package(name)
    return id===nothing ? nothing : dirname(dirname(Base.locate_package(id)))
end


"""
    @srpath(filepath)
    srpath"filepath"

Source-relative path. Equivalent to `joinpath(@__DIR__,filepath)`.

This macro is just a simple modification to `@__DIR__`.

Normally, if writing `MakeDL.cbuild("xxx.cpp")` in a script instead of REPL, it should use `MakeDL.cbuild(srpath"xxx.cpp")` to load `xxx.cpp` related to the script file instead of current working directory.
"""
macro srpath(filepath)
    __source__.file === nothing && throw("Cannot find source-relative path")
    _dirname = dirname(String(__source__.file::Symbol))
    _dirname = isempty(_dirname) ? pwd() : abspath(_dirname)
    return :(joinpath($_dirname, $filepath))
end
@doc (@doc @srpath)
macro srpath_str(filepath)
    return :(@srpath $filepath)
end

# function get_define(str,def_name,def_type::DataType=Any)
#     m=match(Regex("^[ \\t]*#define[ \\t]+$def_name[ \\t]+(.*?)[ \\t]*(?:/[/\\*].*)?\$","m"),str).captures[1]
#     return def_type<:Number ? parse(def_type,m) : m
# end
# function set_define(str,def_name,def_value)
#     replace(str,Regex("(^[ \\t]*#define[ \\t]+$def_name[ \\t]+).*?([ \\t]*(?:/[/\\*].*)?\$)","m"),SubstitutionString("\\g<1>$def_value\\g<2>"))
# end

"""
    rw_define(filename;args...)

Read or write the `#define` statement in C/C++ files. Read means loading the value defined by `#define`; Write means modifying the defined value.

If value of `args` is a data type, then read the define from file;
otherwise, update the define to the new value if different to the old and return the old;
return all the defines as a dict and a boolean to indicate if updated or not.

# Examples

If "t.cpp" has `#define t 1`, then:

- `rw_define("t.cpp",t=Int64)` return `(Dict(:t=>1),false)`
- `rw_define("t.cpp",t=2)` update t.cpp to `#define t 2` and return `(Dict(:t=>1),true)`  
- `rw_define("t.cpp",t=2)` do nothing and return `(Dict(:t=>2),false)`
"""
function rw_define(filename;args...)
    regexp_define=r"(^\s*#define[ \t]+)(\S+)([ \t]+)(.*?)(\s*(?:/[/\*].*)?)$"m
    ret=Dict{Symbol,Any}()
    args=Dict(args)

    lines=readlines(filename,keep=true)
    
    dirty=false
    for i=1:length(lines)
        length(ret)==length(args) && break
        occursin(r"^\s*(/[/\*].*)?$",lines[i]) && continue #only support single line comment
        m=match(regexp_define,lines[i])
        m==nothing && continue
        name=Symbol(m.captures[2])
        val=m.captures[4]
        if haskey(args,name)
            argv=args[name]
            if !isa(argv,Type) #save defines
                vv=string(argv)
                if val!=vv
                    lines[i]=replace(lines[i],regexp_define => SubstitutionString("\\g<1>\\g<2>\\g<3>"*vv*"\\g<5>"))
                    dirty=true
                end
            end

            #parse defines
            argv_t=isa(argv,Type) ? argv : typeof(argv)
            if argv_t<:Number #only parse number type, all other types are kept as string
                t=tryparse(argv_t,val)
                if t != nothing
                    ret[name]=t
                else
                    @warn("cannot convert '$val' to '$argv_t' for '$name'")
                    ret[name]=val
                end
            else
                ret[name]=val
            end
        end
    end
    
    if dirty
        write(filename,lines...)
    end

    return ret,dirty
end

#Main function for building C/C++ code or files
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

    @static if Sys.islinux()
        if output_type=="dll"
            if matlab
                ext=".mexa64"
            else
                ext=".so"
            end
        elseif output_type=="exe"
            ext=""
        elseif output_type=="ptx"
            ext=".ptx"
        elseif output_type=="cpp"
            ext=".ii.cpp"
        end
        compiler=="" && (compiler="g++")
    elseif Sys.iswindows()
        if output_type=="dll"
            if matlab
                ext=".mexw64"
            else
                ext=".dll"
            end
        elseif output_type=="exe"
            ext=".exe"
        elseif output_type=="ptx"
            ext=".ptx"
        elseif output_type=="cpp"
            ext=".ii.cpp"
        end
        compiler=="" && (compiler="cl")
    else
        @error("Unsupported OS")
    end

    if (output_type=="ptx" || output_type=="cpp") && compiler!="nvcc"
        @error("argument 'compiler' should be set to nvcc for output_type $output_type")
    end

    if matlab && output_type!="dll"
        @error("argument 'output_type' souble be set to dll for matlab")
    end

    if matlab_gpu && compiler!="nvcc"
        @error("argument 'compiler' should be set to nvcc for matlab_gpu")
    end

    if code!=""
        tmp_code_file=tempname()
        if compiler=="nvcc"
            tmp_code_file*=".cu"
        elseif compiler=="gcc"
            tmp_code_file*=".c"
        else
            tmp_code_file*=".cpp"
        end
        write(tmp_code_file,code)
        pushfirst!(files,tmp_code_file)
    end

    if output==""
        output=splitext(files[1])[1]
    end
    if splitext(output)[2]!=ext
        _output=output*ext
    else
        _output=output
    end
    if isdir(_output)
        @error("$_output already exists as a folder")
    end
    if _output in files
        error("output cannot be $_output")
    end

    @assert all(isfile.(files))
    @assert all(isfile.(depend_files))
    @assert all(isdir.(include_path))
    @assert all(isdir.(lib_path))
    opencv && @assert isdir(opencv_root) 
    matlab && @assert isdir(matlab_root)
    compiler=="cl" && @assert isfile(vc_env[1])
    compiler=="icl" && @assert isfile(icl_env[1])
    compiler=="gcc" && @assert success(`gcc --version`)
    compiler=="g++" && @assert success(`g++ --version`)
    compiler=="clang" && @assert success(`clang --version`)
    compiler=="nvcc" && @assert success(`nvcc --version`)
    compiler=="nvcc" && Sys.iswindows() && @assert isfile(vc_env[1])

    if force
        need_to_make=true
    else
        need_to_make=false
        for f in [files; depend_files]
            if mtime(f)>mtime(_output)
                need_to_make=true
                break
            end
        end
    end

    if !need_to_make
        if show_cmd
            println("$_output already exists and need not rebuild")
        end
    else
        if opencv
            cv_ver=get_opencv_version(opencv_root)
            if !("world" in opencv_libs)
                upush!(opencv_libs,"core","imgproc") #these two libs are almost always necessary
                if cv_ver>=v"3"
                    upush!(opencv_libs,"imgcodecs")
                end
            end
            @static if Sys.iswindows()
                upush!(include_path,joinpath(opencv_root,"..","..","include"))
                if opencv_static && !isdir(joinpath(opencv_root,"staticlib"))
                    @warn("opencv_static cannot be true")
                    opencv_static=false
                end
                upush!(lib_path,joinpath(opencv_root,opencv_static ? "staticlib" : "lib"))
                opencv_version=string(cv_ver.major)*string(cv_ver.minor)*string(cv_ver.patch)
                tlibs=["opencv_"*s*opencv_version for s in opencv_libs]
                if opencv_static
                    upush!(tlibs,"zlib","libjasper","libjpeg","libpng","libtiff")
                    if cv_ver>=v"2.4.10"
                        upush!(tlibs,"IlmImf")
                    end
                    if "gpu" in opencv_libs
                        @warn("opencv_static may be needed to set to false")
                    end
                end
                if "highgui" in opencv_libs
                    upush!(libs,"comctl32","gdi32","user32","vfw32","ole32","Advapi32","OleAut32")
                end
                for t in tlibs
                    upush!(libs,debug ? t*"d" : t)
                end
            elseif Sys.isunix()
                if cv_ver>=v"4"
                    upush!(include_path,joinpath(opencv_root,"include","opencv4"))
                else                
                    upush!(include_path,joinpath(opencv_root,"include"))
                end
                p=joinpath(opencv_root,"lib")
                upush!(lib_path,p)
                if opencv_rpath
                    upush!(lib_rpath,p)
                end
                uappend!(libs,["opencv_"*s for s in opencv_libs])     
            end
        end

        if julia
            julia_home=dirname(Base.Sys.BINDIR)
            upush!(include_path,joinpath(julia_home,"include","julia"))
            upush!(lib_path,joinpath(julia_home,"lib"))
            upush!(defines,"JULIA_ENABLE_THREADING=1")
            if compiler=="cl" || compiler=="icl"
                upush!(options, "/Zi") #will have error in vs2010 if not use this flag to generate debug information
                upush!(libs,"libjulia.dll.a","libopenlibm.dll.a")
            else
                upush!(lib_rpath,joinpath(julia_home,"lib"))
                upush!(lib_rpath,joinpath(julia_home,"lib","julia"))
                upush!(libs,"julia")
                upush!(options, "-fPIC","-Wl,--export-dynamic")
            end
        end

        if cxxwrap
            cxxwrap_home=pkg_dir("CxxWrap")
            if cxxwrap_home==nothing
                @error("CxxWrap is not installed")
            end
            jlcxx_home=joinpath(cxxwrap_home,"deps","usr")
            julia_home=dirname(Base.Sys.BINDIR)
            upush!(include_path,joinpath(julia_home,"include","julia"))
            upush!(defines,"JULIA_ENABLE_THREADING=1")
            upush!(include_path,joinpath(jlcxx_home,"include"))
            upush!(lib_path,joinpath(jlcxx_home,"lib"))
            @static if Sys.iswindows()
                if compiler!="gcc" || compiler!="g++"
                    @error("cxxwrap is not compatible with vc")
                end
                upush!(libs,"libcxxwrap_julia.dll.a")
            else
                upush!(libs,"cxxwrap_julia")
            end
        end

        if matlab
            upush!(defines,"MATLAB_MEX_FILE")
            upush!(include_path,joinpath(matlab_root,"extern","include"))
            if matlab_gpu
                #upush!(include_path,joinpath(matlab_root,"toolbox","distcomp","gpu","extern","include"))
                upush!(include_path,joinpath(matlab_root,"toolbox","parallel","gpu","extern","include"))
            end

            @static if Sys.iswindows() 
                upush!(libs,"libmx","libmex","libmat")
                if matlab_gpu
                    upush!(libs,"gpu")
                end
                upush!(lib_path,joinpath(matlab_root,"extern","lib","win64","microsoft"))
                #upush!(lib_path,joinpath(matlab_root,"bin","win64")) #should also ok
            else Sys.islinux()
                upush!(libs,"mx","mex","mat")
                if matlab_gpu
                   upush!(libs,"mwgpu")
                end
                upush!(lib_path,joinpath(matlab_root,"bin","glnxa64"))
            end
            upush!(export_names,"mexFunction")
        end

        if debug
            upush!(defines,"_DEBUG") #Visual Studio defines _DEBUG when you specify the /MTd or /MDd option
        else
            upush!(defines,"NDEBUG") #NDEBUG is standard
        end

        #convert libs (support gcc style name, full name, or full path)
        for i=1:length(libs)
            dir,base=splitdir(libs[i])
            name,ext=splitext(base)
            if compiler=="cl" || compiler=="icl"
                if ext==".dll" && dir==""
                    for p in [pwd();lib_path]
                        if isfile(joinpath(p,base))
                            dir=p
                            break
                        end
                    end
                end
                if ext==".dll" && dir==""
                    @error("$(libs[i]) is invalid")
                end
                if ext=="" && dir=="" #emulate gcc style to add "lib" or ".lib" to name
                    for pre in ["","lib"], post in [".lib",".a",".dll.a",".dll"], p in lib_path
                        n=pre*name
                        b=n*post
                        f=joinpath(p,b)
                        if isfile(f)
                            libs[i]=b
                            base=b
                            name=n
                            if post==".dll" #need further processing
                                dir=p
                                ext=post
                            else
                                dir=""
                                ext=""
                            end
                            break
                        end
                    end
                end
                if ext==".dll"
                    @assert dir!=""
                    tmpdir=mktempdir(prefix=name*"_dll_")
                    tmp=joinpath(tmpdir,name);
                    dllpath=joinpath(dir,base)
                    try
                        run(pipeline(`$PEXPORTS $dllpath -o`,stdout=tmp*".def"))
                    catch
                        try
                            run_vc_cmd(vc_env,`dumpbin /exports $dllpath /out:$tmp.def`;show_cmd=false)
                        catch
                            @error("erro when extracting symbols from $dllpath")
                        end
                    end
                    run_vc_cmd(vc_env,`lib /def:$tmp.def /machine:x64 /out:$tmp.lib`;show_cmd=false)
                    libs[i]=name*".lib"
                    dir=""
                    ext=""
                    upush!(lib_path,tmpdir)
                end             
                if dir != ""
                    if isfile(libs[i])
                        upush!(lib_path,dir)
                        libs[i]=base
                    else
                        @error("$(libs[i]) is invalid")
                    end
                elseif ext != ""
                    if isfile(libs[i])
                        upush!(lib_path,pwd())
                    end
                end                    
            else #gcc etc.
                if ext=="" #normal libs
                    if dir != ""
                        @error("$(libs[i]) is invalid")
                    end
                else #specify full lib name or full path
                    if dir != ""
                        if isfile(libs[i])
                            upush!(lib_path,dir)
                            libs[i]=":"*base #enable full lib name
                        else
                            @error("$(libs[i]) is invalid")
                        end
                    else
                        if isfile(libs[i])
                            libs[i]=":"*libs[i]
                            upush!(lib_path,pwd())
                        end
                    end
                end
            end
        end

        if rpath_current
            upush!(lib_rpath,"\${ORIGIN}")
        end
        if rpath
            for p in lib_path
                upush!(lib_rpath,p)
            end
        end

        if compiler=="g++" || compiler=="gcc" || compiler=="clang"
            if output_type=="dll"
                upush!(options, "-fPIC","-shared")
            end
            if debug
                upush!(options,"-g")
            else
                upush!(options,"-O3")
            end
            if openmp
                upush!(options,"-fopenmp")
            end
            if fast_math
                upush!(options,"-ffast-math")
            end
            if fatal_error
                upush!(options,"-Wfatal-errors")
            end
            if !warn
               upush!(options,"-w")  #disable all warnings
            end
            if crt_static
                upush!(options,"-static-libgcc") #normally it is not a good idea to static link to libgcc, sometimes it is OK to static link to libstdc++, almost never static link to libc
            end
            for p in lib_rpath
                upush!(options,"-Wl,-rpath="*p)
            end
            cmd=`$compiler $options -I$include_path -L$lib_path -D$defines -o $_output $files -l$libs -Xlinker\ $link_options`
            run_gcc_cmd(cmd,show_cmd=show_cmd)

        elseif compiler=="cl" || compiler=="icl"
            env = compiler=="icl" ? icl_env : vc_env

            upush!(defines,"_AMD64_")
            
            upush!(options,
                "/nologo",
                "/Fo%temp%\\", #put object file into temp directory
                "/Fd%temp%\\", #put vc100.pdb into temp directory
                "/favor:INTEL64",
                "/EHsc",
            )

            if openmp
                upush!(options,"/openmp")
            end
            if fast_math
                upush!(options,"/fp:fast")
            end
            if !warn
               upush!(options,"/w")  #disable all warnings
            end

            if debug
                upush!(options,
                    crt_static ? "/MTd" : "/MDd",
                    "/Od", #disables optimization
                    "/Zi", #Produces pdb file for debug
                    "/RTC1", #enable run-time error checks
                )
            else
                if compiler=="icl"
                    upush!(options,"/O3")
                else
                    upush!(options,"/O2","/GL")
                end
                upush!(options,crt_static ? "/MT" : "/MD")
            end

            upush!(link_options, "/machine:x64")

            if output_type=="dll"
                upush!(link_options,"/dll")
            end
            if debug
                upush!(link_options,"/DEBUG")
            else
                upush!(link_options,"/INCREMENTAL:no") #disable incremental linking and do not generate .ilk files. vs2010 will have error if not use this
            end

            cmd=`$compiler $options /I$include_path /D$defines $files /link $link_options /export:$export_names /LIBPATH:$lib_path $libs /OUT:$_output`

            run_vc_cmd(env,cmd;show_cmd=show_cmd)
            safe_rm("$output.exp")
            safe_rm("$output.ilk")
            debug || safe_rm("$output.pdb")

        elseif compiler=="nvcc"
            upush!(options,"-m64","-Wno-deprecated-gpu-targets")

            if output_type=="dll"
                upush!(options, "-shared")
            elseif output_type=="ptx"
                upush!(options, "-ptx")
            elseif output_type=="cpp"
                upush!(options, "-cuda")
            end
            if fast_math
                upush!(options,"-use_fast_math")
            end
            if !warn
               upush!(options,"-w")  #disable all warnings
            end
            if debug
                upush!(options,"-g","-G") # -G is for device debug
            else
                upush!(options,"-O3")
            end

            @static if Sys.iswindows() #nvcc will call cl
                push!(options,"-Xcompiler","/Fd%temp%\\") #put vc100.pdb into temp directory
                push!(options,"-Xcompiler",debug ? (crt_static ? "/MTd" : "/MDd") : (crt_static ? "/MT" : "/MD"))
                if output_type=="dll"
                    t=["/export:"].*export_names
                    !isempty(t) && push!(link_options,t...)
                end
            else #nvcc will call gcc
                push!(options,"-Xcompiler","-fPIC")  #key to generate dll
                crt_static && push!(options,"-Xcompiler","-static-libgcc")
                fatal_error && push!(options,"-Xcompiler","-Wfatal-errors")
                for p in lib_rpath
                    push!(options,"-Xlinker", "-rpath="*p)
                end
            end
            nv_link=join(link_options,",") |> t->isempty(t) ? [] : ["-Xlinker",t]

            cmd=`$compiler $options -I$include_path -L$lib_path -D$defines -o $_output $files -l$libs $nv_link`

            @static if Sys.iswindows()
                run_vc_cmd(vc_env,cmd;show_cmd=show_cmd)
                safe_rm("$output.exp")
                safe_rm("$output.ilk")
                debug || safe_rm("$output.pdb")
            elseif Sys.islinux()
                run_gcc_cmd(cmd;show_cmd=show_cmd)
            end

        else
            @error("Unsupported compiler")
        end
    end

    return _output
end
cbuild(files::VStr;args...)=cbuild(;files=files,args...)
cbuild(file::Str;args...)=cbuild(;files=[file],args...)
cbuild_exe(;args...)=cbuild(;output_type="exe",args...)
cbuild_exe(file::Union{Str,VStr};args...)=cbuild(file;output_type="exe",args...)



"""
    @dynamic ccall(...)

Make `ccall` close the opened library immediately and enable its argument to be variable.

`ccall((:function, "library"),...)` is the fastest way to call C libraries, which has no more overhead than calling from C code. However the library opened by `ccall` will not be able to close. If debugging or modifying to the library are necessary after the ccall, you have to restart the Julia process.

It will slow down the speed of ccall but be much better for debugging the library.

Depend on: `using Libdl`

NOTICE: should not be used with openmp

# Examples

    @dynamic ccall( (:clock, "libc.so.6"), Int32, ())

It also enable arguments to be variable, for example:

    name="libc.so.6"
    clock()=@dynamic ccall( (:clock, name), Int32, ())

In this case, after debugging, simply apply @eval to change it to faster normal form of ccall:

    @eval clock()=ccall( (:clock, \$name), Int32, ())
"""
macro dynamic(exp)
    if exp.head!=:call || exp.args[1]!=:ccall || typeof(exp.args[2])!=Expr || exp.args[2].head!=:tuple
        @show exp
        dump(exp)
        @error("unsupported ccall expression")
    end
    func=esc(exp.args[2].args[1])
    dl=esc(exp.args[2].args[2])
    args=map(esc,exp.args[3:end])
    return quote
        let
            h=Libdl.dlopen(string($(dl)))
            try
                ccall(Libdl.dlsym(h,string($func)),$(args...))
            finally
                Libdl.dlclose(h)
                #if the dll uses openmp, then calling dlcose immediately after ccall is not safe, SEE Julia issue#10938
                #even using the following code is still not safe
                # @async begin
                #     sleep(0.01)
                #     Libdl.dlclose(h)
                # end
            end
        end
    end
end

"""
    cfunc(func_name::Str,func_body::Str;args...)  -> func_handle, dll_handle

Convert C/C++ code to callable handle by using `cbuild` to build C/C++ function to dll, using `dlopen` to load the dll, and using `dlsym` to get the function handle for using by `ccall`

# Examples
    
    hfun,hdll = cfunc("foo",\"""extern "C" int foo() {return 1;}\""")
    ccall(hfun,Cint,())
    dlclose(hdll)
"""
function cfunc(func_name::Str,func_body::Str;args...)
    args=Dict{Symbol,Any}(args)
    if haskey(args,:export_names)
        upush!(args[:export_names],func_name)
    else
        args[:export_names]=[func_name]
    end
    if haskey(args,:code)
        @error("should not specify code again")
    else
        args[:code]=func_body
    end
    dllfile=cbuild(;args...)
    if !isfile(dllfile)
        @error("build failed for $dllfile")
    end
    hdll = Libdl.dlopen(dllfile)
    hfun = Libdl.dlsym(hdll,func_name)
    return hfun,hdll
end

"""
    @CC_str(func_body,func_name) -> func_handle

Convert C/C++ code to callable handle

# Examples

    hfun = CC\"""extern "C" int foo() {return 1;}\"""foo
    ccall(hfun,Cint,())

# NOTICE

Because this is a macro, the dll handle returned by cfunc will be opened at compile-time. The dll handle will not be closed.
"""
macro CC_str(func_body,func_name)
    return cfunc(func_name,func_body)[1]
end

"""
    run_cc(code, return_type=Nothing; includes="", args...)

Run piece of C++ code which can return a number. Normally for testing C/C++ code.

# Examples

    run_cc("return sin(1)",Float64)
"""
function run_cc(code, return_type=Nothing; includes="", args...)
    if includes==""
        includes=
        """
            #include <stdlib.h>
            #include <string.h>
            #include <math.h>
        """
    end
    if return_type==Nothing
        return_type_str="void"
    elseif return_type in (Int8,UInt8,Int16,UInt16,Int32,UInt32,Int64,UInt64)
        return_type_str=lowercase(string(return_type)*"_t")
    elseif  return_type==Float32
        return_type_str="float"
    elseif  return_type==Float64
        return_type_str="double"
    else
        @error("unsupported output type")
    end
    args=Dict(args)
    if get(args,:compiler,"")=="gcc"
        @warn "compiler gcc is changed to g++ to build C++ code"
        args[:compiler]="g++"
    end

    hfun,hdll=cfunc("__test_func__",
        """
        #include <stdint.h>
        #include <stdio.h>
        #include <iostream>
        #include <exception>

        $includes

        extern "C" $return_type_str __test_func__()
        {
            struct __finally_type__
            {
                ~__finally_type__() { fflush(stdout); }
            } __finally_instance__;
            try
            {
                $code;
            }
            catch(std::exception& e)
            {
                //printf("error\\n");
                std::cout << e.what() << std::endl;
            }
            $(return_type==Nothing ? "" : "return 0;")
        }
        """; args...)
    try
        return @eval ccall($hfun,$return_type,())
    finally
        Libdl.dlclose(hdll)
    end
end

"""
    run_opencv(code, return_type=Nothing; includes="", args...)

Run piece of C++ code which can use OpenCV and return a number. Normally for testing OpenCV code.

# Examples

    run_opencv("return Mat_<float>(Mat::eye(2,2,CV_32F))(1,1)",Float32)
"""
function run_opencv(code, return_type=Nothing; includes="", args...)
    run_cc(code,return_type;includes="#include <opencv2/opencv.hpp>\nusing namespace cv;\n"*includes,opencv=true,args...)
end

function show_opencv_version(;verbose=false)
    verbose && run_opencv(raw"""printf("%s",getBuildInformation().c_str())""")
    run_opencv(raw"""printf("CV_VERSION: %s\n",CV_VERSION);""")
end

###################################################################

function test()
    #Can use "dllexport" in source code or "exported_names" in cbuild to export symbols. Either way is OK for cl. Both are NOT necessary for gcc.
    dllexport = @static Sys.iswindows() ? "__declspec(dllexport)" : ""
    c_code = """extern "C" $dllexport double inc(double t){return t+1;}"""

    #test1
    let
        @test ccall(cfunc("inc",c_code)[1],Float64,(Float64,),0)==1
    end

    #test2
    let
        hf,hdll=cfunc("csort",raw"""
            #include <algorithm>

            template <class T>
            inline void sort(T* p, int len)
            {
                std::sort(p,p+len);
            }

            extern "C" void csort(int* p, int len)
            {
                sort(p,len);
            }
            """)
        t=rand(Int32,10)
        ccall(hf,Nothing,(Ptr{Int32},Int32),t,length(t))
        @test t==sort(t)
        Libdl.dlclose(hdll)
    end

    #test3
    let
        #use @eval to make the macro is lazily expanded. However, this makes __g_h_test__ be in global name space
        @eval __g_h_test__=CC"""
            extern "C" char* test(char* str)
            {
                return str;
            }
            """test
        @test unsafe_string(ccall(__g_h_test__,Ptr{UInt8},(Ptr{UInt8},),"hello"))=="hello"
    end

    #test4
    let
        @test run_cc("")==nothing
        @test run_cc("return abs(-1)",Int32)==1
        @test run_cc("return std::vector<int>(1).size()",Int32;includes="#include<vector>")==1
        @test run_cc("""return f(10)""",Int32;includes="int f(int i){return i+1;}")==11
        @static if Sys.islinux()
            @test run_cc("return INC(P)",Int32;defines=["INC(x)=x+1","P=3"])==4
        end
        @test run_cc("#ifdef D\nreturn P;\n#else\nreturn 0;\n#endif\n",Int32;defines=["D","P=3"])==3
    end

    #test5
    let
        function test(f)
            hdll=Libdl.dlopen(f);
            hfun=Libdl.dlsym(hdll,"inc");
            @test ccall(hfun,Float64,(Float64,),0)==1
            Libdl.dlclose(hdll)
        end
        test(cbuild(code=c_code,force=true,debug=true,crt_static=false,warn=false,fast_math=true,fatal_error=true))
        test(cbuild(code=c_code,force=true,debug=true,crt_static=true,warn=true,fast_math=true,fatal_error=false))
    end

    #test6, test exe file
    let
        t=cbuild_exe(code="#include <stdio.h>\nint main(){return putchar(0);}")
        @test read(`$t`,String)=="\0"
    end

    #test7, test rpath
    let
        @static if Sys.islinux()
            t=tempname(); dir=dirname(t); bn=basename(t);
            fname=joinpath(dir,"lib"*bn*".cpp")
            write(fname,"extern int test(int t){return t+1;}")
            cbuild(fname;output_type="dll")
            @test run_cc("return test(1);",Cint,includes="extern int test(int t);",libs=[bn],lib_path=[dir],rpath=true)==2
        end
    end

    #test8, test @dynamic
    let
        dll=cbuild(code=c_code,force=true)
        @test @dynamic(ccall(("inc",dll),Float64,(Float64,),0))==1
    end

    #test9, test lib name types
    let
        tmp1=tempname()
        dir=dirname(tmp1)
        bn=basename(tmp1)
        fname=joinpath(dir,"lib"*bn*".cpp")
        write(fname,"""extern "C" char test(char t){return t+1;}""")
        dllpath=cbuild(fname,export_names=["test"]) #dllpath will be dir*"lib"*bn*".so/dll"

        tmp2=tempname()*".cpp"
        open(tmp2,"w") do hf
            write(hf,raw"""
                #include <stdio.h>
                extern "C" char test(char t);
                int main(){putchar(test('a')); return 0;}
                """)
        end
        t2=cbuild_exe(tmp2,libs=[dllpath],rpath=true) #full lib path
        t3=cbuild_exe(tmp2,lib_path=[dir],libs=[basename(dllpath)],rpath=true) #full lib name
        t4=cbuild_exe(tmp2,lib_path=[dir],libs=[bn],rpath=true) #gcc sytle lib name
        @test read(`$t2`,String)==read(`$t3`,String)==read(`$t4`,String)=="b"
        @static if Sys.iswindows()
            t5=cbuild_exe(tmp2,lib_path=[dir],libs=["lib$bn.lib"])
            t6=cbuild_exe(tmp2,lib_path=[dir],libs=["lib$bn"]) #vc style lib name
            t7=cbuild_exe(tmp2,lib_path=[dir],libs=["lib$bn.dll"]) #will generate lib automatically
            @test read(`$t5`,String)==read(`$t6`,String)==read(`$t7`,String)=="b"
        end
    end

    @info "test MakeDL passed"
end

function test_rw_define()
    tmp=tempname()
    content="//#define t 1//t 11\n#define t 1//t 11"
    write(tmp,content)
    @test rw_define(tmp,t=Int64)==(Dict(:t=>1),false) #read
    @test rw_define(tmp,t=2)==(Dict(:t=>1),true) #write
    @test rw_define(tmp,t=2)==(Dict(:t=>2),false) #do nothing
    @test rw_define(tmp,t=1)==(Dict(:t=>2),true) #write
    @test read(tmp,String)==content
    @info "test_rw_define passed"
end

function test_openmp()
    #cannot use run_cc or close dll handle immediately, because if the dll uses openmp, then calling Libdl.dlcose immediately after ccall is not safe, SEE Julia issue#10938
    h1,d1=cfunc("test","""
        extern "C" int test()
        {
            int s=0;
            #pragma omp parallel for reduction(+:s)
            for(int n=0; n<256; ++n) s+=n;
            return s;
        }
        """;openmp=true)
    s1=ccall(h1,Int,())
    h2,d2=cfunc("test","""//slower than reduction
        extern "C" int test()
        {
           int s=0;
            #pragma parallel for 
            for(int n=0; n<256; ++n)
            {
                #pragma omp atomic
                s+=n;
            }
            return s;
        }
       """;openmp=true)
    s2=ccall(h2,Int,())
    @static if Sys.iswindows() #vc only support very few openmp instructions
        @test s1==s2==sum(0:255);
        @info "test_openmp passed"
        return
    end   
    h3,d3=cfunc("test","""//single thread
        extern "C" int test()
        {
           int s=0;
           #pragma omp simd
           for(int n=0; n<256; ++n) s+=n;
           return s;
       }
       """;openmp=true) 
    s3=ccall(h3,Int,())
    h4,d4=cfunc("test","""//slow than atomic
        #include <omp.h>
        extern "C" int test()
        {
            int s=0;
            #pragma omp parallel num_threads(256)
            {
                #pragma omp critical
                s+=omp_get_thread_num();
            }
            return s;
        }
       """;openmp=true)
    s4=ccall(h4,Int,())
    h5,d5=cfunc("test","""
        extern "C" int test()
        {
            int s=0;
            #pragma omp distribute parallel for simd reduction(+:s)
            for(int n=0; n<256; ++n) s+=n;
            return s;
        }
       """;openmp=true)
    s5=ccall(h5,Int,())
    #Libdl.dlclose.((d1,d2,d3,d4,d5))
    @test s1==s2==s3==s4==s5==sum(0:255);
    @info "test_openmp passed"
end

function test_opencv()
    show_opencv_version()
    @test run_opencv("Mat t=(Mat_<int>(2,2)<<1,2,3,4); return sum(t)[0];",Int)==10
    @test run_opencv("Mat t=(Mat_<int>(2,2)<<1,2,3,4); return sum(t)[0];",Int;opencv_static=true,opencv_rpath=false)==10

    #t=eye(2); t[t.==0]=2; t[1:1,:][1,2]
    @test run_opencv("Mat t=Mat::eye(2,2,CV_32F); t.setTo(2,t==0); return t(Range(0,1),Range::all()).at<float>(0,1);",Float32)==2

    #t1=fill(-1,2,2); t2=eye(2); t2[t2.==0]=t1[t2.==0]; sum(t1+t2.!=0)
    @test run_opencv("Mat t1(2,2,CV_32F,-1); Mat t2=Mat::eye(2,2,CV_32F); t1.copyTo(t2,t2==0); return countNonZero(t1+t2);",Float32)==2
    @info "test_opencv passed"
end

function test_opencv_imshow(;args...)
    hf,hdll=cfunc("test", raw"""
        #include <opencv2/opencv.hpp>
        using namespace cv;
        extern "C" void test(void)
        {
            Mat t(100,100,CV_64FC1);
            randu(t,0,1);
            imshow("test",t);
            waitKey(1000); //wait 1 second
            destroyAllWindows();
        }""";opencv=true,force=true,show_cmd=false,args...)
    ccall(hf,Nothing,())
    Libdl.dlclose(hdll)
    @info "test_opencv_imshow passed"
end

function test_opencv_gpu(;args...)
    cv_ver=get_opencv_version(DEFAULT_OPENCV_ROOT)
    if cv_ver<v"3"
        @test run_opencv("Mat s(2,2,CV_32F); randu(s,0,1); gpu::GpuMat d; d.upload(s); gpu::gemm(d,d,1,d,1,d); Mat t; d.download(t); gemm(s,s,1,s,1,s); double m; minMaxLoc(abs(s-t),NULL,&m); return m;",Float32;includes = "#include <opencv2/gpu/gpu.hpp>",opencv_libs=["gpu"])<1e-6
    else
        @test run_opencv("Mat s(2,2,CV_32F); randu(s,0,1); cuda::GpuMat d; d.upload(s); cuda::gemm(d,d,1,d,1,d); Mat t; d.download(t); gemm(s,s,1,s,1,s); double m; minMaxLoc(abs(s-t),NULL,&m); return m;",Float32;includes = "#include <opencv2/cudaarithm.hpp>",opencv_libs=["cudaarithm"])<1e-6
    end
    @info "test_opencv_gpu passed"
end

function test_opencv_ocl(;args...)
    cv_ver=get_opencv_version(DEFAULT_OPENCV_ROOT)
    if cv_ver<v"3"
        @test run_opencv("Mat s(2,2,CV_32F); randu(s,0,1); ocl::oclMat d; d.upload(s); exp(s,s); ocl::oclMat t; t.upload(s); exp(d,d); return ocl::absSum(d-t)[0];",Float32;includes="#include <opencv2/ocl/ocl.hpp>",opencv_libs=["ocl"])<1e-6
    else
        @test run_opencv("ocl::setUseOpenCL(true); Mat s(2,2,CV_32F); randu(s,0,1); UMat d; s.copyTo(d); exp(s,s); UMat t; s.copyTo(t); exp(d,d); return norm(d,t,NORM_INF);",Float32;includes="#include <opencv2/core/ocl.hpp>")<1e-6
    end 
    @info "test_opencv_ocl passed"
end

function test_matlab()
    tmp=mktempdir()
    cppfile=joinpath(tmp,"test.cpp")
    write(cppfile,raw"""
        #include <mex.h>
        void mexFunction(int nlhs, mxArray *plhs[], int nrhs, const mxArray *prhs[])
        {
            mexPrintf("hello\n");
        }
        """)
    t=cbuild(cppfile,matlab=true)
    @test isfile(t)
    @static if Sys.iswindows()
        dlengin=dlopen(joinpath(DEFAULT_MATLAB_ROOT,"bin","win64","libeng.dll"))
    else
        dlengin=dlopen(joinpath(DEFAULT_MATLAB_ROOT,"bin","glnxa64","libeng.so"))
    end
    engin=ccall(dlsym(dlengin,"engOpen"),Ptr{Cvoid},(String,),"")
    @test ccall(dlsym(dlengin,"engEvalString"),Cint,(Ptr{Cvoid},Ptr{UInt8},),engin,"addpath $tmp;test")==0
    ccall(dlsym(dlengin,"engClose"),Cint,(Ptr{Cvoid},),engin)
    @info "test_matlab passed"
    return t #for testing in maltab
end

function test_matlab_gpu()
    tmp=mktempdir()
    cufile=joinpath(tmp,"testgpu.cu")
    write(cufile,raw"""
        #include <mex.h>
        #include <gpu/mxGPUArray.h>
        __global__ void TimesTwo(const double * const A, double * const B, const int N)
        {
            /* Calculate the global linear index, assuming a 1-d grid. */
            int i = blockDim.x * blockIdx.x + threadIdx.x;
            if (i < N) B[i] = 2.0 * A[i];
        }
        //new method to build MEX-Functions containing CUDA code supported after matlab 2013b
        void mexFunction(int nlhs, mxArray *plhs[], int nrhs, const mxArray *prhs[])
        {
            if(nrhs!=1)
            {
                mexErrMsgIdAndTxt("mexGPUExample:InvalidInput", "Invalid input to MEX file.");
            }

            mxInitGPU();
            
            //get the data
            const mxGPUArray *A = mxGPUCreateFromMxArray(prhs[0]); //prhs[0] can be either GPU or CPU data.
            const double *d_A = (const double *)(mxGPUGetDataReadOnly(A));

            //Create a GPUArray to hold the result and get its underlying pointer.
            mxGPUArray *B = mxGPUCreateGPUArray(mxGPUGetNumberOfDimensions(A),
                                    mxGPUGetDimensions(A),
                                    mxGPUGetClassID(A),
                                    mxGPUGetComplexity(A),
                                    MX_GPU_DO_NOT_INITIALIZE);
            double *d_B = (double *)(mxGPUGetData(B));

            //Call the CUDA kernel
            int N = (int)(mxGPUGetNumberOfElements(A));
            const int threadsPerBlock = 256;
            const int blocksPerGrid = (N + threadsPerBlock - 1) / threadsPerBlock;
            TimesTwo<<<blocksPerGrid, threadsPerBlock>>>(d_A, d_B, N);

            //make the returned array is either on GPU or on CPU according to the input
            if(mxIsGPUArray(prhs[0]))
                plhs[0] = mxGPUCreateMxArrayOnGPU(B);
            else
                plhs[0] = mxGPUCreateMxArrayOnCPU(B);

            //The mxGPUArray pointers are host-side structures that refer to device
            //data. These must be destroyed before leaving the MEX function.
            mxGPUDestroyGPUArray(A);
            mxGPUDestroyGPUArray(B);
        }
        """)
    t=cbuild(cufile,matlab=true,matlab_gpu=true,compiler="nvcc")
    @test isfile(t)
    @info "test_matlab_gpu passed"
    return t #for testing in maltab
end

function test_cuda()
    @test run_cc("return abs(-1)",Int;compiler="nvcc")==1
    @test run_cc("return abs(-1)",Int;force=true,debug=true,fatal_error=true,compiler="nvcc")==1
    @test run_cc("return abs(-1)",Int;fast_math=true,crt_static=true,compiler="nvcc")==1
    @test run_cc("#ifdef D\nreturn P;\n#else\nreturn 0;\n#endif\n",Int,defines=["D","P=3"],compiler="nvcc")==3
    @info "test_cuda passed"
end

function test_cuda_ptx_cpp()
    tmp=tempname()*".cu"
    write(tmp,raw"""
        __global__ void TimesTwo(const double* A, double* B, int N)
        {
            /* Calculate the global linear index, assuming a 1-d grid. */
            int i = blockDim.x * blockIdx.x + threadIdx.x;
            if (i < N) B[i] = 2.0 * A[i];
        }
        """)
    t1=cbuild(tmp,output_type="ptx",compiler="nvcc")
    t2=cbuild(tmp,output_type="cpp",compiler="nvcc")
    @static if Sys.isunix()
        t3=cbuild(t2,show_cmd=true) #currently not work for widnows
        @test isfile(t3)
    end
    @test isfile(t1) && isfile(t2)
    @info "test_cuda_ptx_cpp passed"
end

function test_cuda_opencv()
    @test run_opencv("Mat t=(Mat_<int>(2,2)<<1,2,3,4); return sum(t)[0];",Int;show_cmd=true,opencv_rpath=true,compiler="nvcc",warn=false)==10
    @test run_opencv("Mat t=(Mat_<int>(2,2)<<1,2,3,4); return sum(t)[0];",Int;opencv_static=true,opencv_rpath=true,compiler="nvcc",warn=false)==10
    @info "test_cuda_opencv passed"
end

function test_cuda_kernel(;args...)
    hf,hdll=cfunc("test", raw"""
        __global__ void TimesTwo(const double* A, double* B, int N)
        {
            /* Calculate the global linear index, assuming a 1-d grid. */
            int i = blockDim.x * blockIdx.x + threadIdx.x;
            if (i < N) B[i] = 2.0 * A[i];
        }

        extern "C" void test(const double* A, double* B, int N)
        {
            //copy data from CPU to GPU
            double *d_A;
            cudaMalloc(&d_A, N*sizeof(double));
            cudaMemcpy(d_A, A, N*sizeof(double), cudaMemcpyHostToDevice);
        
            //allocate device memory to hold the result
            double *d_B;
            cudaMalloc(&d_B, N*sizeof(double));
        
            //Call the CUDA kernel
            const int threadsPerBlock = 256;
            const int blocksPerGrid = (N + threadsPerBlock - 1) / threadsPerBlock;
            TimesTwo<<<blocksPerGrid, threadsPerBlock>>>(d_A, d_B, N);

            //copy data from GPU to CPU
            cudaMemcpy(B, d_B, N*sizeof(double), cudaMemcpyDeviceToHost);

            cudaFree(d_A);
            cudaFree(d_B);

            cudaDeviceReset();
        }
        """;compiler="nvcc",force=true,show_cmd=true,args...)
    N=8
    A=rand(N)
    B=zeros(N)
    ccall(hf,Nothing,(Ptr{Float64},Ptr{Float64},Cint),A,B,N)
    Libdl.dlclose(hdll)
    @test A*2.0==B;
    @info "test_cuda_kernel passed"
end

function test_cuda_vsadu4()
    code="""
        unsigned int vsadu4(unsigned int a, unsigned int b)
        {
            unsigned char* pa=(unsigned char*)&a;
            unsigned char* pb=(unsigned char*)&b;
            return abs(pa[0]-pb[0])+abs(pa[1]-pb[1])+abs(pa[2]-pb[2])+abs(pa[3]-pb[3]);
        }
        """
    code_norm="""
            #include <math.h>
            extern "C" $code
            """
    code_simd="""
            //use GCC SIMD vector instructions
            extern "C" unsigned int vsadu4(unsigned int a, unsigned int b)
            {
                typedef char v8qi __attribute__ ((vector_size(8)));
                typedef long long int v1di __attribute__ ((vector_size(8)));
                char* pa=(char*)&a;
                char* pb=(char*)&b;   
                v1di v=__builtin_ia32_psadbw((v8qi){pa[0],pa[1],pa[2],pa[3],0,0,0,0},(v8qi){pb[0],pb[1],pb[2],pb[3],0,0,0,0});
                return ((unsigned int*)&v)[0];
            }
            """
    code_cuda="""
            __host__ __device__ $code
            __global__ void kernel(unsigned int A, unsigned int B, unsigned int* out)
            {
                /* Calculate the global linear index, assuming a 1-d grid. */
                int i = blockDim.x * blockIdx.x + threadIdx.x;
                if(i==0) out[0] = __vsadu4(A,B); //Use CUDA SIMD Intrinsics. CUDA_VERSION should be above 7050
                else if(i==1) out[1] = vsadu4(A,B);
            }
            extern "C" void test(unsigned int A, unsigned int B, unsigned int* out)
            {
                unsigned int *d_out;
                cudaMalloc(&d_out, 2*sizeof(unsigned int));
                kernel<<<1, 2>>>(A, B, d_out);
                cudaMemcpy(out, d_out, 2*sizeof(unsigned int), cudaMemcpyDeviceToHost);
                cudaFree(d_out);
                out[2] = vsadu4(A,B);
            }
            """
    hf_cuda,hdll_cuda=cfunc("test",code_cuda;compiler="nvcc");
    hf_norm,hdll_norm=cfunc("vsadu4",code_norm);
    A=rand(UInt32)
    B=rand(UInt32)
    out=UInt32[0,0,0];
    ccall(hf_cuda,Nothing,(UInt32,UInt32,Ptr{UInt32}),A,B,out)
    norm = ccall(hf_norm,UInt32,(UInt32,UInt32),A,B)
    Libdl.dlclose(hdll_cuda)
    Libdl.dlclose(hdll_norm)
    @test out[1]==out[2]==out[3]==norm
    @static if Sys.isunix()
        hf_simd,hdll_simd=cfunc("vsadu4",code_simd;compiler="g++");
        simd = ccall(hf_simd,UInt32,(UInt32,UInt32),A,B)
        Libdl.dlclose(hdll_simd)
        @test out[1]==simd
    end
    @info "test_cuda_vsadu4 passed"
end

function test_julia()
    main_cpp=tempname()*".cpp"
    embed_jl=tempname()*".jl"
    write(main_cpp,"""
        #include <stdio.h>
        #include <julia.h>
        JULIA_DEFINE_FAST_TLS()

        void call(jl_function_t* sqr1, int* x, int len)
        {
            jl_value_t* array_type = jl_apply_array_type((jl_value_t*)jl_int32_type, 1);
            jl_array_t* ax = jl_ptr_to_array_1d(array_type,x,len,0);
            jl_array_t* ay = (jl_array_t*)jl_call1(sqr1, (jl_value_t*)ax);
            int* py = (int*)jl_array_data(ay);
            for(int i=0;i<jl_array_len(ay);++i) printf("%d ",py[i]);
        }

        int main()
        {
            jl_init();
            jl_module_t* m = (jl_module_t *)jl_load(jl_main_module,"$(escape_string(embed_jl))");
            jl_function_t* f = jl_get_function(m, "sqr1");
            int x[] = {2,4,5};
            call(f,x,3);
            jl_atexit_hook(0);
            return 0;
        }
        """)
    write(embed_jl,"""
        module embed
            function sqr1(x::Array{T,1}) where{T<:Number}
                return abs2.(x) .+ T(1)
            end
        end
        """)
    t=cbuild(main_cpp,output_type="exe",julia=true)
    @test readchomp(`$t`) == "5 17 26 "
    @info "test_julia passed"
end

function test_cxxwrap()
    pkg_dir("CxxWrap")==nothing && @error("CxxWrap is not installed")
    ext_cpp=tempname()*".cpp"
    main_jl=tempname()*".jl"
    write(ext_cpp,"""
        #include "jlcxx/jlcxx.hpp"
        std::string greet()
        {
           return "hello, world";
        }
        JLCXX_MODULE define_julia_module(jlcxx::Module& mod)
        {
          mod.method("greet", &greet);
        }
        """)
    t=cbuild(ext_cpp,cxxwrap=true)
    write(main_jl,"""
        module CppHello
            using CxxWrap
            @wrapmodule("$t")
            function __init__()
                @initcxx
            end
        end
        println(CppHello.greet())
        """)
    @test readchomp(`julia $main_jl`)=="hello, world"
    @info "test_cxxwrap passed"
end

function test_package_compiler()
    pkg_dir("PackageCompiler")==nothing && @error("PackageCompiler is not installed")
    tmp=mktempdir()
    
    tmp1=joinpath(tmp,"foo.cpp")
    write(tmp1,"""extern "C" char foo(char t){return t+1;}""")
    t1=cbuild(tmp1,export_names=["foo"])
    
    tmp2=joinpath(tmp,"callfoo.jl")
    write(tmp2,"""
        module CallFoo
            Base.@ccallable callfoo(s::Cchar)::Cchar = ccall((:foo,raw"$t1"),Cchar,(Cchar,),s)
        end
        """)
    t2="libcallfoo"
    ex="""using PackageCompiler;
        build_shared_lib(raw"$tmp2",raw"$t2",builddir=raw"$tmp",optimize="0",compile="no",init_shared=true)
        """
    run(`julia -e "$ex"`)
    t2=joinpath(tmp, t2*(Sys.iswindows() ? ".dll" : ".so"))
    
    tmp3=joinpath(tmp,"main.cpp")
    open(tmp3,"w") do hf
        write(hf,"""
            #include <stdio.h>
            extern "C" void init_jl_runtime();
            extern "C" void exit_jl_runtime(int);
            extern "C" char callfoo(char);
            int main(){init_jl_runtime();putchar(callfoo('a'));exit_jl_runtime(0);return 0;}
            """)
    end
    t3=cbuild_exe(tmp3,libs=[t2],rpath=true)
    @test read(`$t3`,String)=="b"
    @info "test_package_compiler passed"
end

function test_essential()
    test()
    test_rw_define()
    test_openmp()
    test_opencv()
    test_opencv_imshow()
    test_opencv_ocl()
    test_julia()
    pkg_dir("PackageCompiler")!=nothing && test_package_compiler()
    nothing
end

function test_all()
    test()
    test_rw_define()
    test_openmp()
    test_opencv()
    test_opencv_imshow()
    test_opencv_gpu()
    test_opencv_ocl()
    test_matlab()
    test_matlab_gpu()
    test_cuda()
    test_cuda_ptx_cpp()
    test_cuda_opencv()
    test_cuda_kernel()
    test_cuda_vsadu4()
    test_julia()
    pkg_dir("CxxWrap")!=nothing && test_cxxwrap()
    pkg_dir("PackageCompiler")!=nothing && test_package_compiler()
    nothing
end

end
