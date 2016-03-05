#
# common config values for all jsonar projects
#
if(NOT DEFINED CMAKE_CXX_STANDARD)
  set(CMAKE_CXX_STANDARD 14)
endif()
set(CMAKE_CXX_EXTENSIONS OFF)

include(InstallRequiredSystemLibraries)
include(FindPkgConfig)

if(NOT CMAKE_BUILD_TYPE)
  message(STATUS "No build type selected, default is Release")
  set(CMAKE_BUILD_TYPE "Release" CACHE STRING "Build type" FORCE)
endif()

set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

include(GNUInstallDirs)
include(SonarFunctions)
