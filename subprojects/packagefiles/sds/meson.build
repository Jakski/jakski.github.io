project('sds', 'c')

sds_inc = include_directories('.')
sds_lib = static_library(
    'sds',
    [
        'sds.c',
    ],
    include_directories: sds_inc,
)

sds_dep = declare_dependency(
    link_with: sds_lib,
    include_directories: sds_inc,
)
