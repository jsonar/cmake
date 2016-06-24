include(SonarFunctions)

if(CMAKE_INSTALL_PREFIX_INITIALIZED_TO_DEFAULT)
  message(STATUS "No install prefix defined, default is /usr")
  set(CMAKE_INSTALL_PREFIX "/usr" CACHE PATH "Package install prefix" FORCE)
endif()

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

set(CPACK_SET_DESTDIR true)
set(CPACK_PACKAGE_VENDOR "jsonar")
set(CPACK_PACKAGE_LICENSE "2016 jSonar Inc")
set(CPACK_PACKAGE_URL "http://www.jsonar.com")
set(CPACK_PACKAGE_CONTACT "jSonar Support <support@jsonar.com>")
if (NOT DEFINED CPACK_PACKAGE_DESCRIPTION_SUMMARY)
  set(CPACK_PACKAGE_DESCRIPTION_SUMMARY "${PROJECT_NAME} built by jSonar")
endif()

if(NOT DEFINED CPACK_PACKAGE_NAME)
  string(TOLOWER ${PROJECT_NAME} CPACK_PACKAGE_NAME)
endif()
if (CPACK_GENERATOR STREQUAL "RPM")
  set(CPACK_RPM_PACKAGE_LICENSE ${CPACK_PACKAGE_LICENSE})
  set(CPACK_RPM_PACKAGE_URL ${CPACK_PACKAGE_URL})
  set(CPACK_RPM_PACKAGE_GROUP "Applications/Databases")
  set(CPACK_RPM_PACKAGE_DESCRIPTION ${CPACK_PACKAGE_DESCRIPTION})
  execute_process(COMMAND uname "-m"
    OUTPUT_VARIABLE CPACK_RPM_PACKAGE_ARCHITECTURE
    OUTPUT_STRIP_TRAILING_WHITESPACE)
  execute_process(
    COMMAND rpm "-q" "--queryformat" "%{RELEASE}" rpm
    COMMAND rev
    COMMAND cut "-d." "-f1"
    COMMAND rev
    OUTPUT_VARIABLE RHEL
    OUTPUT_STRIP_TRAILING_WHITESPACE)

  if (CPACK_RPM_PACKAGE_REQUIRES)
    if (RHEL STREQUAL "el6")
      string(REPLACE "python34u" "python34"
        CPACK_RPM_PACKAGE_REQUIRES ${CPACK_RPM_PACKAGE_REQUIRES})
      string(REPLACE "python34" "python34u"
        CPACK_RPM_PACKAGE_REQUIRES ${CPACK_RPM_PACKAGE_REQUIRES})
      string(REPLACE "python3-pip" "python34u-pip"
        CPACK_RPM_PACKAGE_REQUIRES ${CPACK_RPM_PACKAGE_REQUIRES})
    elseif(RHEL STREQUAL "el7")
      string(REPLACE "mysql" "mariadb"
        CPACK_RPM_PACKAGE_REQUIRES ${CPACK_RPM_PACKAGE_REQUIRES})
    endif()
  endif()

  set (CPACK_PACKAGE_FILE_NAME
    "${CPACK_PACKAGE_NAME}-${CPACK_PACKAGE_VERSION_MAJOR}.${CPACK_PACKAGE_VERSION_MINOR}.${CPACK_PACKAGE_VERSION_PATCH}${CPACK_PACKAGE_VERSION_EXTRA}.${RHEL}.${CPACK_PACKAGE_VENDOR}.${CPACK_RPM_PACKAGE_ARCHITECTURE}")

  list(APPEND CPACK_RPM_EXCLUDE_FROM_AUTO_FILELIST_ADDITION
    "${CPACK_PACKAGING_INSTALL_PREFIX}/${CMAKE_INSTALL_LIBDIR}/pkgconfig")
elseif(CPACK_GENERATOR STREQUAL "DEB")
  execute_process(COMMAND dpkg "--print-architecture"
    OUTPUT_VARIABLE CPACK_DEBIAN_PACKAGE_ARCHITECTURE
    OUTPUT_STRIP_TRAILING_WHITESPACE)
  set(CPACK_DEBIAN_PACKAGE_SHLIBDEPS ON)
  string(REPLACE "-" "~" DEBIAN_VERSION_NUMBER
    "${CPACK_PACKAGE_VERSION_MAJOR}.${CPACK_PACKAGE_VERSION_MINOR}.${CPACK_PACKAGE_VERSION_PATCH}${CPACK_PACKAGE_VERSION_EXTRA}")
  if (NOT DEFINED DEBIAN_REVISION)
    set(DEBIAN_REVISION 1)
  endif()
  execute_process(COMMAND lsb_release "-ir"
    COMMAND cut "-f2"
    COMMAND xargs
    COMMAND tr "[ [:upper:]]" "[+[:lower:]]"
    OUTPUT_VARIABLE DEBIAN_OS
    OUTPUT_STRIP_TRAILING_WHITESPACE)
  set(DEBIAN_REVISION_NUMBER "${DEBIAN_REVISION}${DEBIAN_OS}")
  set(CPACK_PACKAGE_FILE_NAME
    "${CPACK_PACKAGE_NAME}_${DEBIAN_VERSION_NUMBER}-${DEBIAN_REVISION_NUMBER}_${CPACK_DEBIAN_PACKAGE_ARCHITECTURE}")
endif()

set_property (GLOBAL PROPERTY TARGET_MESSAGES OFF)
string(TOLOWER ${CPACK_GENERATOR} CPACK_PACKAGE_EXT)
add_custom_target(package_file_name echo ${CPACK_PACKAGE_FILE_NAME}.${CPACK_PACKAGE_EXT})

include(CPack)
