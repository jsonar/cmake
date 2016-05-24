#
# common config values for all jsonar projects
#
if(NOT DEFINED CMAKE_CXX_STANDARD)
  set(CMAKE_CXX_STANDARD 14)
endif()
set(CMAKE_CXX_EXTENSIONS OFF)

include(InstallRequiredSystemLibraries)
include(FindPkgConfig)

set(CMAKE_BUILD_TYPE "Release" CACHE STRING "Build type")
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

include(GNUInstallDirs)
include(SonarFunctions)

string(TOLOWER ${CMAKE_PROJECT_NAME} CMAKE_PROJECT_NAME_LOWER)
install(FILES eula.txt
  DESTINATION share/doc/${CMAKE_PROJECT_NAME_LOWER}
  PERMISSIONS OWNER_READ OWNER_WRITE GROUP_READ WORLD_READ
  )
