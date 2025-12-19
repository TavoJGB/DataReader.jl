module DataReader

    using CSV           # for .csv
    using DataFrames

    BASE_FOLDER = dirname(@__DIR__)

    # Load dependencies
    include(joinpath(BASE_FOLDER, "src", "dep", "utils.jl"))
    include(joinpath(BASE_FOLDER, "src", "dep", "read_files.jl"))
    export read_database, read_simple_database
end
