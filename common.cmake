#
# common config values for all jsonar projects
#
if(NOT DEFINED CMAKE_CXX_STANDARD)
  set(CMAKE_CXX_STANDARD 14)
endif()
set(CMAKE_CXX_EXTENSIONS OFF)

include(InstallRequiredSystemLibraries)
include(FindPkgConfig)

if (NOT CMAKE_BUILD_TYPE)
  set(CMAKE_BUILD_TYPE "RelWithDebInfo" CACHE STRING "Build type" FORCE)
endif()
message(STATUS "Build Type: ${CMAKE_BUILD_TYPE}")
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

include(SonarFunctions)

if(CMAKE_INSTALL_PREFIX_INITIALIZED_TO_DEFAULT)
  set(CMAKE_INSTALL_PREFIX "" CACHE PATH "Package install prefix" FORCE)
endif()

find_program(CCACHE ccache)
if(CCACHE)
  message(STATUS "Found ccache at ${CCACHE}")
  set(CMAKE_C_COMPILER_LAUNCHER ${CCACHE})
  set(CMAKE_CXX_COMPILER_LAUNCHER ${CCACHE})
endif()

include(GNUInstallDirs)
include(SonarExternal)

string(TOLOWER ${CMAKE_PROJECT_NAME} CMAKE_PROJECT_NAME_LOWER)

## install eula to separate component packages
foreach(component ${SONAR_COMPONENTS})
  install(FILES ${CMAKE_CURRENT_LIST_DIR}/eula.txt
    DESTINATION share/doc/${component}
    COMPONENT ${component}
    PERMISSIONS OWNER_READ OWNER_WRITE GROUP_READ WORLD_READ
    )
endforeach()

## install eula to default location if no components
if (NOT SONAR_COMPONENTS)
  install(FILES ${CMAKE_CURRENT_LIST_DIR}/eula.txt
    DESTINATION share/doc/${CMAKE_PROJECT_NAME_LOWER}
    COMPONENT ${component}
    PERMISSIONS OWNER_READ OWNER_WRITE GROUP_READ WORLD_READ
   )
endif()

# only enable component variables if SONAR_COMPONENTS 
# has been set in the project
if (SONAR_COMPONENTS)
  foreach(gen RPM DEB)
    set(CPACK_${gen}_COMPONENT_INSTALL ON)
    set(CPACK_${gen}_PACKAGE_COMPONENT ON)
  endforeach()
endif()
