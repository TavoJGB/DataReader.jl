# DEPRECATED
# function raw_reader(filepath::String; kwargs...)
#     ext = lowercase(splitext(filepath)[2])
#     if ext==".csv"
#         return CSV.read(filepath, DataFrame; kwargs...)
#     elseif ext == ".dta"
#         return DataFrame(load(filepath))
#     else
#         error("Unsupported file format: $ext")
#     end
# end



#==========================================================================
    BASIC FILE READING
==========================================================================#

"""
    load_fileset(datadir::String, identifiers, filefinder::Vector{<:Function}, args...; kwargs...) -> DataFrame

Load and merge multiple data files corresponding to a set of identifiers (e.g. year, imputation).

# Arguments
- `datadir`: Directory containing data files.
- `identifiers`: Tuple or NamedTuple of identifiers (e.g. year, imputation).
- `filefinder`: Function to find filepath(s) based on datadir and identifiers.
- `id_key`: Only for multiple files: the key to merge on (e.g. household ID).
- `kwargs...`: Additional keyword arguments to pass to CSV.read (e.g. `select` for variable selection).

# Returns
DataFrame.
"""

load_fileset(filepath::String; kwargs...) = CSV.read(filepath, DataFrame; kwargs...)
function load_fileset(filepaths::Vector{<:String}, id_key; delim=";", makeunique::Bool=false, kwargs...)
    # Load first file
    main = CSV.read(filepaths[1], DataFrame; kwargs...)
    nr = nrow(main)
    # Merge subsequent files
    for file in filepaths[2:end]
        df = CSV.read(file, DataFrame; kwargs...)
        # Verify same number of rows
        nr == nrow(df) || throw(ErrorException("Files in the same fileset but of different size"))
        # Merge on key
        leftjoin!(main, df; on=id_key, makeunique)
    end
    return main
end
load_fileset(datadir::String, identifiers, filefinder::Function, args...; kwargs...) = load_fileset(filefinder(datadir; identifiers...), args...; kwargs...)



#==========================================================================
    AUXILIARY CALLERS
==========================================================================#

# No iteration on identifiers
function process_simple_set(
    datafile::String, id_key, vars::DataFrame=DataFrame();
    c_vars = Dict(zip(vars.varkey, vars.varname)),
    select = Symbol.([keys(c_vars)...; id_key]),
    postprocess::Function = (df, args...) -> df,
    kwargs...
)

    # Load raw data
    df = load_fileset(datafile; select, kwargs...)

    # Rename variables
    rename!(df, c_vars)
    
    # Apply post-processing (e.g., compute derived variables)
    return postprocess(df, vars)
end

# Iterate over identifiers
function process_simple_set(
    datadir::String, identifiers, id_key, vars::DataFrame=DataFrame();
    c_vars = get_current_variables(vars; identifiers...),
    select = Symbol.([keys(c_vars)...; id_key]),
    filefinder::Function,
    postprocess::Function = (df, args...) -> df,
    kwargs...
)

    # Load raw data
    df = load_fileset(datadir, identifiers, filefinder, id_key; select, kwargs...)

    # Add identifiers
    for (key, val) in pairs(identifiers)
        df[!, key] .= val
    end

    # Rename variables
    rename!(df, c_vars)
    
    # Apply post-processing (e.g., compute derived variables)
    return postprocess(df, vars)
end



#==========================================================================
    DATABASE READER
==========================================================================#

# No iteration (f.e. no iteration over years, i.e. no identifiers)
function read_database(
    datafile::String,
    id_key;
    verbose::Bool=true,
    varlists_dir::String=joinpath(pwd(), "var_lists"),
    preprocess::Function = vars -> vars,
    varlist_filename::String="vars.csv",
    comment::String="#",
    get_select_fn::Union{Function, Nothing} = nothing,
    kwargs... # filefinder, get_current_variables, postprocess, c_vars, select
)
    # Initialize results
    df = DataFrame()
    
    # Lists of variables
    vars = preprocess(CSV.read(joinpath(varlists_dir, varlist_filename), DataFrame; comment))

    # Compute select if function provided
    if get_select_fn !== nothing
        select = get_select_fn(vars)
        kwargs = merge((; select), kwargs)
    end

    # Process dataset
    return process_simple_set(datafile, id_key, vars; kwargs...)
end

# Iterating over waves/years
function read_database(
    datadir::String,
    identifier_ranges::Tuple{Vararg{Pair{Symbol, <:AbstractVector}}},
    get_id_key::Function;
    verbose::Bool=true,
    varlists_dir::String=joinpath(datadir, "var_lists"),
    preprocess::Function = vars -> vars,
    varlist_filename::String="vars.csv",
    comment::String="#",
    kwargs... # filefinder, get_current_variables, postprocess, c_vars, select
)
    # Initialize results
    df = DataFrame()
    
    # Lists of variables
    vars = preprocess(CSV.read(joinpath(varlists_dir, varlist_filename), DataFrame; comment))

    # Process each identifier
    for identifiers in expand_identifiers(identifier_ranges...)
        # Process this identifier
        temp = process_simple_set(datadir, identifiers, get_id_key(; identifiers...), vars; kwargs...)
        
        # Append data
        if nrow(df) == 0
            df = temp
        else
            df = vcat(df, temp; cols=:union)
        end
        
        verbose && @info "$(string(identifiers)) included"
    end
    
    return df
end



#==========================================================================
    GENERALIZED MULTI-DATASET CASE
==========================================================================#

# Auxiliary caller: process one identifier set with N varlists
function process_multilevel_set(
    datadir::String, identifiers, id_key, vars::DataFrame;
    id_name::Symbol=:hid,
    filefinder::Function,
    postprocess::Function = (dfs...) -> dfs,
    do_rename::Bool=true,
    kwargs... # get_current_variables
)
    raw = load_fileset(datadir, identifiers, filefinder, id_key; kwargs...)

    # Variables of interest
    varlists = [filter(:level => (lv -> lv==x), vars) for x in unique(vars.level)]

    # Build one dataframe per varlist
    dfs = DataFrame[]
    for vs in varlists
        c_vars = get_current_variables(vs; identifiers...)
        cols = find_columns(raw, c_vars)
        temp = select(raw, cols)
        temp[!, id_name] = raw[!, id_key]

        for (key, val) in pairs(identifiers)
            temp[!, key] .= val
        end

        do_rename && rename!(temp, c_vars)
        push!(dfs, temp)
    end
    
    # Apply post-processing (e.g., compute derived variables)
    return postprocess(dfs..., varlists...)
end

# Database reader
function read_multilevel_database(
    datadir::String,
    identifier_ranges::Tuple{Vararg{Pair{Symbol, <:AbstractVector}}},
    get_id_key::Function;
    verbose::Bool=true,
    varlists_dir::String=joinpath(datadir, "var_lists"),
    preprocess::Function = (args...) -> args,
    varlist_filename::String="vars.csv",
    comment::String="#",
    kwargs... # filefinder, get_current_variables, postprocess
)    

    # Lists of variables
    vars = preprocess(CSV.read(joinpath(varlists_dir, varlist_filename), DataFrame; comment))

    # Initialize results
    ndatasets = vars.level |> unique |> length
    full_dfs = [DataFrame() for _ in 1:ndatasets]

    # Process each identifier
    for identifiers in expand_identifiers(identifier_ranges...)
        # Process this identifier
        temp_dfs = process_multilevel_set(datadir, identifiers, get_id_key(; identifiers...), vars; kwargs...)

        length(temp_dfs) == ndatasets || throw(ErrorException("postprocess must return $ndatasets dataset(s)"))

        # Append data
        for i in eachindex(full_dfs)
            if nrow(full_dfs[i]) == 0
                full_dfs[i] = temp_dfs[i]
            else
                full_dfs[i] = vcat(full_dfs[i], temp_dfs[i]; cols=:union)
            end
        end
        
        verbose && @info "$(string(identifiers)) included"
    end
    
    return full_dfs
end

# Auxiliary caller to pass key directly, instead of a function
function read_multilevel_database(
    datadir::String, identifier_ranges::Tuple, id_key; kwargs...)
    return read_multilevel_database(
        datadir, identifier_ranges,
        (; kwargs...) -> id_key;
        kwargs...
    )
end