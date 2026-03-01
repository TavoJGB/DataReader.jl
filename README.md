# DataReader

[![Build Status](https://github.com/TavoJGB/DataReader.jl/actions/workflows/CI.yml/badge.svg?branch=main)](https://github.com/TavoJGB/DataReader.jl/actions/workflows/CI.yml?query=branch%3Amain)

`DataReader.jl` is a Julia package to load and harmonize datasets.



## Installation

```julia
using Pkg
Pkg.add(url="https://github.com/TavoJGB/DataReader.jl")
```

```julia
using DataReader
```


## Core concepts

- **Raw files** are read with `CSV.read`.
- **Varlists** map raw variable names to harmonized names across time.
- **Identifier ranges** are expanded to all combinations (for example all `year, imputation` pairs).
- **filefinder** is a user-provided function that resolves path(s) for each identifier combination.



## API

### `read_database`

Use this when you want a single output `DataFrame`.

#### Single-file mode

The simplest case: reading a single file with all the data.

```julia
read_database(
	datafile::String,
	id_key;
	varlists_dir::String=joinpath(pwd(), "var_lists"),
	varlist_filename::String="vars.csv",
	preprocess::Function = vars -> vars,
	comment::String="#",
	kwargs...
)
```

Additional keyword arguments forwarded to the processing pipeline:

| Kwarg | Default | Description |
|---|---|---|
| `postprocess` | `(df, vars) -> df` | Function applied after loading and renaming. |
| `get_select_fn` | `nothing` | If provided, a function `vars -> select` that determines which columns to read. When `nothing`, columns are inferred from `c_vars`. |
| `c_vars` | `get_current_variables(vars)` | A `Dict{String,String}` mapping raw names to harmonized names. |
| `do_rename` | `true` | Whether to rename columns using `c_vars`. |



#### Iterative mode (multiple identifiers)

Use this mode when your dataset is split into multiple subsets defined by identifiers (for example, data including several waves, or data with multiple imputations for the same subjects). For each combination of identifiers (in the previous example, for each year and/or imputation), DataReader can read one file or merge several files by key.

```julia
read_database(
	datadir::String,
	identifier_ranges::Tuple{Vararg{Pair{Symbol, <:AbstractVector}}},
	get_id_key::Function;
	varlists_dir::String=joinpath(datadir, "var_lists"),
	varlist_filename::String="vars.csv",
	preprocess::Function = vars -> vars,
	comment::String="#",
	kwargs...
)
```

Additional keyword arguments forwarded to the processing pipeline:

| Kwarg | Default | Description |
|---|---|---|
| `filefinder` | *(required)* | Function `(dir; identifiers...) -> filepaths` to locate data files. |
| `postprocess` | `(df, vars) -> df` | Function applied after loading and renaming. |
| `variable_mapper` | `get_current_variables` | Function `(vars; identifiers...) -> Dict{String,String}` that builds the variable mapping for each identifier set. |
| `get_select_fn` | `nothing` | If provided, a function `vars -> select` for column selection. |
| `do_rename` | `true` | Whether to rename columns using the variable mapping. |

Returns one harmonized `DataFrame`.

### `read_multilevel_database`

Use this when your data includes variables at multiple `level`s (for example, individual- and household-level data). DataReader will provide one output dataframe per level.

```julia
read_multilevel_database(
	datadir::String,
	identifier_ranges::Tuple{Vararg{Pair{Symbol, <:AbstractVector}}},
	get_id_key::Function;
	varlists_dir::String=joinpath(datadir, "var_lists"),
	varlist_filename::String="vars.csv",
	preprocess::Function=(args...) -> args,
	comment::String="#",
	kwargs...
)
```

Additional keyword arguments forwarded to the processing pipeline:

| Kwarg | Default | Description |
|---|---|---|
| `filefinder` | *(required)* | Function `(dir; identifiers...) -> filepaths` to locate data files. |
| `postprocess` | `(dfs...) -> dfs` | Function applied after building per-level DataFrames. |
| `variable_mapper` | `get_current_variables` | Function `(vars; identifiers...) -> Dict{String,String}` that builds the variable mapping for each identifier set and level. |
| `do_rename` | `true` | Whether to rename columns using the variable mapping. |

Also available with direct key:

```julia
read_multilevel_database(datadir, identifier_ranges, id_key; kwargs...)
```

Returns a `Vector{DataFrame}` (one per unique `level` found in varlist order).



## Varlists

A **varlist** tells DataReader what variables to extract from the raw data and how to rename them. They can be used to harmonise variables potentially changing names across files, years, or waves.

### Minimum required columns

`vars.csv` must include at least:

- `varname`: output (harmonized) name.
- `varkey`: raw source name.

### For time-windowed data

When using `variable_mapper=get_time_filtered_variables` (for datasets where variable names change across waves, like the SCF or EFF), the varlist must also include:

- `firsttime`: first year/period where this variable mapping is valid.
- `lasttime`: last year/period where this variable mapping is valid.

### For `read_multilevel_database`

`vars.csv` must include the previous columns plus:

- `level`: dataset level label used to split outputs.



## Exported functions

### `get_current_variables(varlist; kwargs...) -> Dict{String,String}`

Generic default variable mapper. Maps every `varkey` to `varname` in the varlist without filtering. Used as the default `variable_mapper`.

### `get_time_filtered_variables(varlist; year, kwargs...) -> Dict{String,String}`

Specialized variable mapper for time-windowed data. Keeps only rows where `firsttime <= year <= lasttime`. Pass it as `variable_mapper=get_time_filtered_variables` when your varlist includes `firsttime`/`lasttime` columns (e.g., SCF, EFF).


## Useful customization hooks

- `postprocess`: transform outputs after each processed identifier set. For example, to reshape one subset or to generate additional variables.
- `preprocess`: transform varlists before reading. For example, to ensure that some variables necessary for internal computations in `postprocess` are extracted, even if not required by the user.
- `variable_mapper`: control how the variable mapping (`varkey` → `varname`) is built for each identifier set. The default (`get_current_variables`) maps all rows; use `get_time_filtered_variables` for datasets with time-varying variable names.
- `get_select_fn`: inject a custom column-selection function instead of relying on the default (which selects columns matching `c_vars` keys + `id_key`).
- `do_rename`: set to `false` to skip automatic renaming (useful when `postprocess` handles renaming itself).
- CSV keyword arguments (`kwargs...`) are forwarded to `CSV.read`.



## Usage examples
- [ReadEFF.jl](https://github.com/TavoJGB/ReadEFF.jl): Uses `read_multilevel_database` with `variable_mapper=get_time_filtered_variables` to extract individual- and household-level data from multiple files, across different waves and imputations. With `preprocess`/`postprocess`, the code deals with variables not present in all waves, extends varlists, reshapes individual-level data from wide to long format, and computes derived household variables (e.g., net wealth and housing tenure).
- [ReadNLSY.jl](https://github.com/TavoJGB/ReadNLSY.jl): Uses `read_database` (single-file mode) with `do_rename=false` and a custom `get_select_fn`, since NLSY variable lists don't use `firsttime`/`lasttime`. All reshaping and renaming is handled in `postprocess`, which converts wide NLSY structures into long panel/roster formats.
- [ReadSCF.jl](https://github.com/TavoJGB/ReadSCF.jl): Uses iterative `read_database` with `variable_mapper=get_time_filtered_variables` and a custom `filefinder` to load SCF waves and put them together (each wave is split in more than one file). It then applies a lightweight `postprocess` for harmonization, typing, and final variable selection.



## License

See [LICENSE](LICENSE).

