add_executable(marisa-build
  marisa-build.cc
  cmdopt.cc
)

target_link_libraries(marisa-build
  marisa
)

install(TARGETS marisa-build
  DESTINATION "${CMAKE_INSTALL_PREFIX}/bin"
)
