module DataReader

    using CSV           # for .csv
    using DataFrames

    BASE_FOLDER = dirname(@__DIR__)

    # Load dependencies
    include(joinpath(BASE_FOLDER, "src", "dep", "utils.jl"))
    include(joinpath(BASE_FOLDER, "src", "dep", "read_files.jl"))
    export read_database, read_multilevel_database, get_current_variables, get_time_filtered_variables, get_selected_varnames
end
