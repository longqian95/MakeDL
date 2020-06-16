#const DEFAULT_VC_ENV = [raw"C:\Program Files (x86)\Microsoft Visual Studio 10.0\VC\vcvarsall.bat","amd64"] #vs2010
#const DEFAULT_VC_ENV = [raw"C:\Program Files (x86)\Microsoft Visual Studio 12.0\VC\vcvarsall.bat","amd64"] #vs2013
const DEFAULT_VC_ENV = [raw"C:\Program Files (x86)\Microsoft Visual Studio\2019\Community\VC\Auxiliary\Build\vcvarsall.bat","x64"] #vs2019 Community

const DEFAULT_ICL_ENV = [raw"C:\Program Files (x86)\Intel\Composer XE 2011 SP1\bin\ipsxe-comp-vars.bat","vs2010","intel64"]

@static if Sys.iswindows()
    const DEFAULT_MATLAB_ROOT = raw"C:\MATLAB\R2016b"
else
    const DEFAULT_MATLAB_ROOT = success(`which matlab`) ? dirname(dirname(readchomp(`which matlab`))) : ""
end

@static if Sys.iswindows()
    const DEFAULT_OPENCV_ROOT = raw"C:\opencv3.4.8\build\x64\vc15"
else
    const DEFAULT_OPENCV_ROOT = success(`which opencv_version`) ? dirname(dirname(readchomp(`which opencv_version`))) : ""
    #const DEFAULT_OPENCV_ROOT = "/opt/opencv2.4.13.7"
    #const DEFAULT_OPENCV_ROOT = "/opt/opencv3.4.10"
    #const DEFAULT_OPENCV_ROOT = "/opt/opencv4.3.0"
end

const DEFAULT_OPENCV_LIBS = ["world"]
#const DEFAULT_OPENCV_LIBS = ["calib3d","highgui"] #"core" and "imgproc" are always included in `cbuild` function

