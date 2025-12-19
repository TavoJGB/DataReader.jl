#==========================================================================
    AUXILIARY FUNCTIONS
==========================================================================#

"""
    read_varlist_file(filepath::String) -> DataFrame

Read a CSV file containing variable names and return as DataFrame.
Lines starting with # are treated as comments.
The var list file should have the following columns:
- `varname`: the name that we want to use in our analysis.
- `varkey`: the name of the variable in the raw data files.
- `firsttime`: the first year in which this variable appears.
- `lasttime`: the last year in which this variable appears.

# Arguments
- `filepath`: Path to the CSV file with variable definitions

# Returns
DataFrame with columns for variable mappings across years
"""
function read_varlist_files(
    varlists_dir::String;
    i_list_filename::String="ivars.csv", h_list_filename::String="hvars.csv", comment::String="#")
    ivars = CSV.read(joinpath(varlists_dir, i_list_filename), DataFrame; comment)
    hvars = CSV.read(joinpath(varlists_dir, h_list_filename), DataFrame; comment)
    return ivars, hvars
end
function read_simple_varlist_files(
    varlists_dir::String;
    list_filename::Union{String, Nothing}="vars.csv", comment::String="#"
)
    return CSV.read(joinpath(varlists_dir, list_filename), DataFrame; comment)
end



"""
    expand_identifiers(ranges::Pair{Symbol, <:AbstractVector}...)

Create all combinations of identifier ranges as NamedTuples.

# Arguments
- `ranges`: Pairs of Symbol => range (e.g., :year => 2002:3:2020, :imputation => 1:5)

# Returns
Vector of NamedTuples with all combinations

# Examples
```julia
# Simple example
ids = expand_identifiers(:year => 2002:2005, :imputation => 1:2)
# Returns: [(year=2002, imputation=1), (year=2002, imputation=2), 
#           (year=2005, imputation=1), (year=2005, imputation=2)]

# For EFF
ids = expand_identifiers(:year => 2002:3:2020, :imputation => 1:5)
# Returns: [(year=2002, imputation=1), ..., (year=2020, imputation=5)]

# Multiple dimensions
ids = expand_identifiers(:wave => 1:3, :region => ["North", "South"], :version => 1:2)
```
"""
function expand_identifiers(ranges::Pair{Symbol, <:AbstractVector}...)
    # Start from last one
    inv_ranges = reverse(ranges)
    # Extract keys and values
    keys = [p.first for p in inv_ranges]
    values = [collect(p.second) for p in inv_ranges]
    # Create all combinations using Iterators.product
    combinations = Iterators.product(values...)
    # Convert to vector of NamedTuples
    return [NamedTuple{reverse(Tuple(keys))}(reverse(combo)) for combo in combinations][:]
end


function find_columns(
    df::DataFrame, vars::Dict;
    var_matcher::Function = (name, col) -> startswith(col, name * "_")
)
    return vcat([filter(col -> var_matcher(string(var), string(col)), names(df)) for var in keys(vars)]...)
end
function find_columns(
    df::DataFrame, ivars::Dict, hvars::Dict;
    ivar_matcher::Function = (name, col) -> startswith(col, name * "_"),
    hvar_matcher::Function = (name, col) -> (col == name)
)
    ivar_cols = vcat([filter(col -> ivar_matcher(string(var), string(col)), names(df)) for var in keys(ivars)]...)
    hvar_cols = vcat([filter(col -> hvar_matcher(string(var), string(col)), names(df)) for var in keys(hvars)]...)
    return ivar_cols, hvar_cols
end



function pivot_longer(
    wide::AbstractDataFrame, id_cols::Vector{Symbol}, vars::Dict;
    pivot_key::Symbol=:individual
)
    dfs = DataFrame[]   
    # Iterate on variables
    for (varkey, varname) in vars
        temp = stack(wide, Regex("^$(varkey)_\\d+\$"), id_cols, 
                     variable_name=pivot_key, value_name=varkey) #value_name=varname)
            # I could rename directly here by setting value_name=varname
            # but then I need to make a difference with non-pivoted
            # sets, that would need to be renamed in a different place.
        # Extract pivot identifier from column name: e.g., "varname_1" => pivot id = "1"
        temp[!, pivot_key] = [parse(Int, split(String(x), "_")[end]) for x in temp[!, pivot_key]]
        push!(dfs, temp)
    end
    # Join all
    long = dfs[1]
    for i in 2:length(dfs)
        long = outerjoin(long, dfs[i]; on=vcat(id_cols, pivot_key))
    end
    return long
end



"""
    verify_append_integrity(df_full::DataFrame, df_new::DataFrame,
                           identifier_filter::Function,
                           identifier_label::String="")

Verify that newly appended data has expected dimensions.

# Arguments
- `df_full`: Full accumulated DataFrame
- `df_new`: Newly processed DataFrame to append
- `identifier_filter`: Function to filter df_full to current identifier
  - Input: row -> Bool
  - Example: row -> row.year == 2020 && row.imputation == 1
- `identifier_label`: String label for error messages (e.g., "Year 2020, Imputation 1")

# Throws
Error if data integrity checks fail, warning if columns are missing

# Example
```julia
# For EFF with year and imputation
filter_fn = row -> row.year == (year-1) && row.imputation == imputation
label = "Year \$year, Imputation \$imputation"
verify_append_integrity(full_df, new_df, filter_fn, label)
```
"""
function verify_append_integrity(df_full::DataFrame, df_new::DataFrame,
                                identifier_filter::Function,
                                identifier_label::String="")
    # Filter to current identifier
    current = filter(identifier_filter, df_full)
    
    n_full, n_new = nrow(current), nrow(df_new)
    ncols_full, ncols_new = ncol(current), ncol(df_new)
    
    prefix = isempty(identifier_label) ? "" : "$identifier_label: "
    
    if n_full > n_new
        error("$(prefix)Rows appear to be repeated in full dataset")
    elseif n_full < n_new
        error("$(prefix)Rows appear to be missing in full dataset")
    elseif ncols_full < ncols_new
        error("$(prefix)Columns appear to be missing in full dataset")
    elseif ncols_full > ncols_new
        @warn "$(prefix)Some variables from previous identifiers are missing"
    end
    
    return nothing
end