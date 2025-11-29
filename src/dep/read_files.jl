"""
    load_fileset(datadir::String, identifiers, filefinder::Vector{<:Function}, args...; kwargs...) -> DataFrame

Load and merge multiple data files corresponding to a set of identifiers (e.g. year, imputation).

# Arguments
- `datadir`: Directory containing EFF data files.
- `identifiers`: Tuple or NamedTuple of identifiers (e.g. year, imputation).
- `filefinder`: Function to find file path(s) based on datadir and identifiers.

# Returns
Merged DataFrame with all sections.
"""

load_fileset(filepath::String; kwargs...) = CSV.read(filepath, DataFrame; kwargs...)
function load_fileset(filepaths::Vector{<:String}, id_key; kwargs...)
    # Load first file
    main = CSV.read(filepaths[1], DataFrame; kwargs...)
    nr = nrow(main)
    # Merge subsequent files
    for file in filepaths[2:end]
        df = CSV.read(file, DataFrame; kwargs...)   
        # Verify same number of rows
        nr == nrow(df) || throw(ErrorException("Files in the same fileset but of different size"))
        # Merge on key
        main = leftjoin(main, df; on=id_key)
    end
    return main
end
load_fileset(datadir::String, identifiers, filefinder::Function, args...; kwargs...) = load_fileset(filefinder(datadir; identifiers...), args...; kwargs...)



function extract_individuals_and_households(df::DataFrame, ivars::Dict, hvars::Dict, hid_key; kwargs...)    
    # Identify columns
    icols, hcols = find_columns(df, ivars, hvars; kwargs...)
    # Extract
    df_ii = select(df, icols)
    df_hh = select(df, hcols)
    # Ensure that both datasets include household identifier
    df_ii.hid = df[!, hid_key]
    df_hh.hid = df[!, hid_key]
    return df_ii, df_hh
end



function process_set(
    datadir::String, identifiers, id_key;
    filefinder::Function,
    varlists_dir::String=joinpath(datadir, "var_lists"),
    get_current_variables::Function,
    postprocess::Function = (dfs...) -> dfs,
    kwargs...   #ifile_name, hfile_name
)
    raw = load_fileset(datadir, identifiers, filefinder, id_key; delim=";")

    # Variables of interest
    all_ivars, all_hvars = read_varlist_files(varlists_dir; kwargs...)
    # - Current variables
    ivars = get_current_variables(all_ivars; identifiers...)
    hvars = get_current_variables(all_hvars; identifiers...)
    # - Extract individual and household dataframes
    df_ii_wide, df_hh = extract_individuals_and_households(raw, ivars, hvars, id_key)
    # - Add identifiers
    for (key, val) in pairs(identifiers)
        df_ii_wide[!, key] .= val
        df_hh[!, key] .= val
    end

    # Reshape individual dataframe from wide to long
    id_vars = [keys(identifiers)..., :hid]
    df_ii = pivot_longer(df_ii_wide, id_vars, ivars)

    # Rename variables
    rename!(df_ii, ivars)
    rename!(df_hh, hvars)
    
    # Apply post-processing (e.g., compute derived variables)
    return postprocess(df_ii, df_hh)
end


function read_database(
    datadir::String,
    identifier_ranges::Tuple{Vararg{Pair{Symbol, <:AbstractVector}}},
    get_id_key::Function;
    progress_label::Function=string,
    kwargs... # filefinder, varlists_dir, get_current_variables, postprocess, ifile_name, hfile_name
)    
    # Initialize results
    df_hh = DataFrame()
    df_ii = DataFrame()
    
    # Process each identifier
    for identifiers in expand_identifiers(identifier_ranges...)
        # Process this identifier
        temp_ii, temp_hh = process_set(datadir, identifiers, get_id_key(; identifiers...); kwargs...)
        
        # Append data
        if nrow(df_ii) == 0
            df_ii = temp_ii
        else
            df_ii = vcat(df_ii, temp_ii; cols=:union)
        end
        if nrow(df_hh) == 0
            df_hh = temp_hh
        else
            df_hh = vcat(df_hh, temp_hh; cols=:union)
        end
        
        @info "$(progress_label(identifiers)) included"
    end
    
    return df_ii, df_hh
end
function read_database(
    datadir::String, identifier_ranges::Tuple, id_key; kwargs...)
    return read_database(
        datadir, identifier_ranges,
        (; kwargs...) -> id_key;
        kwargs...
    )
end