module DataReader

    using CSV
    using DataFrames

    BASE_FOLDER = dirname(@__DIR__)

    # Load dependencies
    include(joinpath(BASE_FOLDER, "src", "dep", "utils.jl"))
    include(joinpath(BASE_FOLDER, "src", "dep", "read_files.jl"))
    export read_database
end
