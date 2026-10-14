# bhinsights-ref-files

## `ttwa_postcode_xwalk.csv.gz`

Every UK postcode (live and terminated) mapped to its 2011 Travel to Work Area.
Built by `prepare_ttwa_postcode_xwalk.R` from the May 2025 ONS Postcode
Directory and the ONS TTWA (December 2011) names file.

| column    | example     |
|-----------|-------------|
| `pcds`    | `AB1 0AA`   |
| `ttwa`    | `S22000047` |
| `ttwa_nm` | `Aberdeen`  |

2,714,964 rows. Postcodes with no TTWA, plus the Channel Islands
(`L99999999`) and Isle of Man (`M99999999`) pseudo-codes, have a blank name.

It is a plain CSV, gzipped to fit under GitHub's file limit. Most tools read it
directly:

```r
readr::read_csv('ttwa_postcode_xwalk.csv.gz', col_types = readr::cols(.default = 'c'))
```

```python
pd.read_csv('ttwa_postcode_xwalk.csv.gz', dtype=str)
```

or `gunzip -k ttwa_postcode_xwalk.csv.gz` to get the CSV. Don't open the
unzipped CSV in Excel: it has more rows than Excel can hold, and Excel will
cut it off without warning.

Contains OS data © Crown copyright and database right 2025.
Contains Royal Mail data © Royal Mail copyright and database right 2025.
Contains GeoPlace data © Local Government Information House Limited copyright
and database right 2025.
Source: Office for National Statistics, licensed under the Open Government
Licence v3.0.
