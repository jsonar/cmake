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
  set(CMAKE_BUILD_TYPE "Release" CACHE STRING "Build type" FORCE)
endif()
message(STATUS "Build Type: ${CMAKE_BUILD_TYPE}")
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

if(CMAKE_INSTALL_PREFIX_INITIALIZED_TO_DEFAULT)
  message(STATUS "No install prefix defined, default is /usr")
  set(CMAKE_INSTALL_PREFIX "/usr" CACHE PATH "Package install prefix" FORCE)
endif()


include(GNUInstallDirs)
include(SonarFunctions)
include(SonarExternal)

string(TOLOWER ${CMAKE_PROJECT_NAME} CMAKE_PROJECT_NAME_LOWER)
if (NOT SONAR_COMPONENTS)
  set(SONAR_COMPONENTS ${CMAKE_INSTALL_DEFAULT_COMPONENT_NAME})
endif()
foreach(component ${SONAR_COMPONENTS})
  install(FILES ${CMAKE_CURRENT_LIST_DIR}/eula.txt
    DESTINATION share/doc/${component}
    COMPONENT ${component}
    PERMISSIONS OWNER_READ OWNER_WRITE GROUP_READ WORLD_READ
    )
endforeach()
foreach(gen RPM DEB)
  set(CPACK_${gen}_COMPONENT_INSTALL ON)
  set(CPACK_${gen}_PACKAGE_COMPONENT ON)
endforeach()
