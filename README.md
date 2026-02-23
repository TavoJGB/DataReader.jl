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
	postprocess::Function = (df, vars) -> df,
	get_select_fn::Union{Function, Nothing}=nothing,
	comment::String="#",
	kwargs...
)
```



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
	postprocess::Function = (df, vars) -> df,
	filefinder::Function,
	comment::String="#",
	kwargs...
)
```

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
	postprocess::Function=(dfs...) -> dfs,
	filefinder::Function,
	comment::String="#",
	kwargs...
)
```

Also available with direct key:

```julia
read_multilevel_database(datadir, identifier_ranges, id_key; kwargs...)
```

Returns a `Vector{DataFrame}` (one per unique `level` found in varlist order).



## Varlists

A **varlist** tells DataReader what variables to extract from the raw data and how to rename them. They can be used to harmonise variables potentially changing names across files, years, or waves.

### For `read_database`

`vars.csv` must include:

- `varname`: output (harmonized) name.
- `varkey`: raw source name.
- `firsttime`: first year/period where variable exists.
- `lasttime`: last year/period where variable exists.

### For `read_multilevel_database`

`vars.csv` must include the previous columns plus:

- `level`: dataset level label used to split outputs.



## Useful customization hooks

- `postprocess`: transform outputs (a `DataFrame` from `read_database` or a `Vector{DataFrame}` from `read_multilevel_database`) after each processed identifier set. For example, to reshape one subset or to generate additional variables.
- `preprocess`: transform varlists before reading. For example, to ensure that some variables necessary for internal computations in `postprocess` are extracted, even if not required by the user.
- CSV keyword arguments (`kwargs...`) are forwarded to `CSV.read`.



## Usage examples
- [ReadEFF.jl](https://github.com/TavoJGB/ReadEFF.jl): Uses `read_multilevel_database` to extract individual- and household-level data from multiple files, across different waves and imputations. With `preprocess`/`postprocess`, the code extends varlists, reshapes individual-level data from wide to long format, and compute derived household variables (e.g., net wealth and housing tenure).
- [ReadNLSY.jl](https://github.com/TavoJGB/ReadNLSY.jl): Uses `read_database` (single-file mode) multiple times, to extract the main data as well as optional roster files. Relying on `postprocess`, it converts wide NLSY structures into long panel/roster formats.
- [ReadSCF.jl](https://github.com/TavoJGB/ReadSCF.jl): Uses iterative `read_database` with `identifier_ranges` and a custom `filefinder` to load SCF waves and put them together (each wave is split in more than one file). It then applies a lightweight `postprocess` for harmonization, typing, and final variable selection.



## License

See [LICENSE](LICENSE).

