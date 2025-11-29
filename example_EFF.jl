using DataReader

# Preliminaries
datadir = joinpath(pwd(), "..", "IWTdata", "data", "eff")
hid_key=get_household_id_var(; year::Int, kwargs...) =  year == 2002 ? "h_number" : "h_$(year)"
identifier_ranges = (:year => 2002:3:2020, :imputation => 1:5)
filefinder(dir::String; year::Int, imputation::Int) = [
    joinpath(dir, "section6_$(year)_imp$(imputation).csv");
    joinpath(dir, "other_sections_$(year)_imp$(imputation).csv")
]
function get_current_variables(varlist; year::Int, kwargs...)
    # Filter rows valid for this year
    valid_rows = (varlist.firsttime .<= year) .& (varlist.lasttime .>= year)
    
    # Create mapping: standardized name => EFF column name
    return Dict(zip(varlist[valid_rows, :varkey], varlist[valid_rows, :varname]))
end

# Read EFF
df_ii, df_hh = read_database(
    datadir, identifier_ranges, get_household_id_var;
    filefinder, get_current_variables, ifile_name="eff_vars_ii.csv", hfile_name="eff_vars_hh.csv"
)