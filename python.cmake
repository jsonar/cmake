function(python_pip_dependencies _deps)
  if (NOT DEFINED CPACK_GENERATOR)
    sonar_cpack_generator(CPACK_GENERATOR)
  endif()
  if (${CPACK_GENERATOR} STREQUAL "RPM")
    foreach(python_pkg pip)
      foreach(python_ver python python27 python26 python34u)
        set(package ${python_ver}-${python_pkg})
        execute_process(
          COMMAND rpm "--quiet" "-q" ${package}
          RESULT_VARIABLE rv)
        if (${rv} EQUAL 0)
          execute_process(
            COMMAND rpm "-q" "--queryformat" "%{NAME}" ${package}
            OUTPUT_VARIABLE dep)
          list(APPEND deplist ${dep})
        endif()
      endforeach()
    endforeach()
  elseif(${CPACK_GENERATOR} STREQUAL "DEB")
    foreach(python_pkg pip)
      foreach(python_ver python python2.7 python2.6 python3 python3.4)
        set(package ${python_ver}-${python_pkg})
        execute_process(
          COMMAND dpkg-query "--show" "--showformat" "\${Package}" ${package}
          ERROR_QUIET
          OUTPUT_VARIABLE dep)
        list(APPEND deplist ${dep})
      endforeach()
    endforeach()
  endif()
  if (deplist)
    string(REPLACE ";" ", " deps "${deplist}")
  endif()
  message(STATUS "Python dependencies: ${deps}")
  set(${_deps} "${deps}" PARENT_SCOPE)
endfunction()
