include(SonarFunctions)

if (NOT DEFINED CPACK_GENERATOR)
  sonar_cpack_generator(CPACK_GENERATOR)
endif()

if (NOT DEFINED CPACK_PACKAGING_INSTALL_PREFIX)
  set(CPACK_PACKAGING_INSTALL_PREFIX "/")
endif()

if (NOT DEFINED CPACK_PACKAGE_VERSION_MAJOR)
  sonar_cpack_version(CPACK_PACKAGE_VERSION_MAJOR
    CPACK_PACKAGE_VERSION_MINOR
    CPACK_PACKAGE_VERSION_PATCH)
endif()

#
# CPACK_SET_DESTDIR allows packaging of files installed in absolute
# directories (e.g. /etc/) However, it affects extrenal projects as well, so
# they end up in the parent project's package.  To avoid that, use `$(MAKE)
# DESTDIR=<INSTALL_PREFIX> install` when installing an external project.
set(CPACK_SET_DESTDIR ON)

sonar_vendor(OUTPUT_VARIABLE CPACK_PACKAGE_VENDOR)
string(TIMESTAMP this_year "%Y")
set(CPACK_PACKAGE_LICENSE "${this_year} jSonar Inc") 
set(CPACK_PACKAGE_URL "http://www.jsonar.com")
set(CPACK_PACKAGE_CONTACT "jSonar Support <support@jsonar.com>")
if (NOT DEFINED CPACK_PACKAGE_DESCRIPTION_SUMMARY)
  set(CPACK_PACKAGE_DESCRIPTION_SUMMARY "${PROJECT_NAME} built by jSonar")
endif()

if(NOT DEFINED CPACK_PACKAGE_NAME)
  string(TOLOWER ${PROJECT_NAME} CPACK_PACKAGE_NAME)
endif()
set_package_and_file_name_for_component(FILE_NAME ${CPACK_PACKAGE_NAME} COMPONENT ${CPACK_PACKAGE_NAME})
if (CPACK_GENERATOR STREQUAL "RPM")
  set(CPACK_RPM_PACKAGE_LICENSE ${CPACK_PACKAGE_LICENSE})
  set(CPACK_RPM_PACKAGE_URL ${CPACK_PACKAGE_URL})
  set(CPACK_RPM_PACKAGE_GROUP "Applications/Databases")
  set(CPACK_RPM_PACKAGE_DESCRIPTION ${CPACK_PACKAGE_DESCRIPTION})
elseif(CPACK_GENERATOR STREQUAL "DEB")
  set(CPACK_DEBIAN_PACKAGE_SHLIBDEPS ON)  # @todo: probably default
endif()
set_property (GLOBAL PROPERTY TARGET_MESSAGES OFF)
string(TOLOWER ${CPACK_GENERATOR} CPACK_PACKAGE_EXT)
if(NOT SONAR_COMPONENTS)
  add_custom_target(package_file_name
    COMMAND echo ${CPACK_PACKAGE_FILE_NAME}.${CPACK_PACKAGE_EXT})
else()
  add_custom_target(package_file_name)
  foreach(component ${SONAR_COMPONENTS})
    if(CPACK_${component}_FILE_NAME)
      if (CPACK_GENERATOR STREQUAL "DEB")
        set(CPACK_DEBIAN_${component}_FILE_NAME ${CPACK_${component}_FILE_NAME}.${CPACK_PACKAGE_EXT}) 
      else()
        set(CPACK_${CPACK_GENERATOR}_${component}_FILE_NAME ${CPACK_${component}_FILE_NAME}.${CPACK_PACKAGE_EXT}) 
      endif()
      add_custom_target(package_file_name-${component}
        COMMAND echo ${CPACK_${component}_FILE_NAME}.${CPACK_PACKAGE_EXT})
    endif()
    add_dependencies(package_file_name package_file_name-${component})
  endforeach()
endif()

if (CMAKE_BUILD_TYPE STREQUAL "Debug")
  # Do not strip debug symbols from the package.
  #
  # collected from various posts in the rpm and cmake mailing lists. Not sure
  # all three defs are needed, but it works.
  #
  set(CPACK_RPM_SPEC_MORE_DEFINE "
%define debug_package %{nil}
%define __strip /bin/true
%define __spec_install_port /usr/lib/rpm/brp-compress
")
endif()

include(CPack)
