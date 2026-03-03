#==========================================================================
    AUXILIARY FUNCTIONS
==========================================================================#

"""
    get_current_variables(varlist::DataFrame; kwargs...) -> Dict{String,String}

Generic default: maps varkey => varname for all rows without filtering.
"""
function get_current_variables(varlist::DataFrame; kwargs...)
    isempty(varlist) && return Dict{String,String}()
    return Dict(zip(varlist.varkey, varlist.varname))
end

"""
    get_time_filtered_variables(varlist::DataFrame; year::Int, kwargs...) -> Dict{String,String}

Specialized version for time-windowed data (e.g., EFF, SCF).
Filters rows where `firsttime <= year <= lasttime`.
"""
function get_time_filtered_variables(varlist::DataFrame; year::Int, kwargs...)
    isempty(varlist) && return Dict{String,String}()
    valid_rows = @. (varlist.firsttime <= year) & (varlist.lasttime >= year)
    return Dict(zip(varlist[valid_rows, :varkey], varlist[valid_rows, :varname]))
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
    var_matcher::Function = (name, col) -> (startswith(col, name * "_") || (col == name))
)
    return vcat([filter(col -> var_matcher(string(var), string(col)), names(df)) for var in keys(vars)]...)
end



function pivot_longer(
    wide::AbstractDataFrame, id_cols::Vector{Symbol}, vars::Dict;
    pivot_key::Symbol=:individual, pivot_sep::String="_"
)
    # Escape special regex characters in separator
    escaped_sep = join([c in ".^\$*+?{}[]\\|()" ? "\\" * c : string(c) for c in pivot_sep])
    
    dfs = DataFrame[]   
    # Iterate on variables
    for (varkey, varname) in vars
        rgx = Regex("^$(varkey)$(escaped_sep)\\d+\$")
        matching_cols = filter(col -> occursin(rgx, string(col)), names(wide))
        if isempty(matching_cols)
            @warn "pivot_longer: no columns matching regex $(rgx) for varkey '$(varkey)' — skipping"
            continue
        end
        temp = stack(wide, rgx, id_cols,
                     variable_name=pivot_key, value_name=varkey)
        # Extract pivot identifier from column name: e.g., "varname_1" => pivot id = "1"
        temp[!, pivot_key] = [parse(Int, split(String(x), pivot_sep)[end]) for x in temp[!, pivot_key]]
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
