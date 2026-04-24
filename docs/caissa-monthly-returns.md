# Caissa monthly return batch script

The script at `scripts/caissa_batch_monthly_returns.py` reads a fund list from `.csv`, `.tsv`, or `.xlsx` and exports monthly return rows from the `v0` fund return endpoints.

## What it does

1. Reads your input file.
2. Resolves each fund by `fundCode` or exact `fundName`.
3. Pulls the fund's available return sources.
4. Selects one return source:
   - safest default: do not auto-pick if multiple sources exist
   - optional: use `--preferred-source-types` for a global preference order
   - safest per-row: include `returnSourceType`, `returnSourceId`, or `returnSourceNameContains`
5. Calls `/v0/funds/returns` with `Periodicity=Monthly`.
6. Writes:
   - an output CSV with one row per month
   - an issues CSV for unresolved rows and warnings

## Input columns

Supported headers are case-insensitive. The script recognizes these columns:

- `fundCode`
- `fundName`
- `returnSourceType`
- `returnSourceNameContains`
- `returnSourceId`
- `notes`

You only need one of `fundCode` or `fundName`, but `fundCode` is safer when you have it.

### Recommended input pattern

- Use `fundCode` whenever possible.
- Add `returnSourceType` if a fund may have more than one return source.
- Add `returnSourceNameContains` when there can be multiple sources of the same type and you want a specific one.

## Token setup

The script expects a bearer token that already works against the client API.

Use either:

- `--token YOUR_TOKEN`
- `CAISSA_BEARER_TOKEN=YOUR_TOKEN`

The script does not implement the login flow itself.

## Example commands

CSV input:

```powershell
$env:CAISSA_BEARER_TOKEN = "paste-token-here"
python scripts/caissa_batch_monthly_returns.py `
  --input docs/fund-return-input-template.csv `
  --output outputs/monthly_returns.csv `
  --date-from 2022-01-01T00:00:00Z `
  --date-to 2026-03-31T23:59:59Z
```

XLSX input from a specific sheet:

```powershell
$env:CAISSA_BEARER_TOKEN = "paste-token-here"
python scripts/caissa_batch_monthly_returns.py `
  --input C:\path\to\funds.xlsx `
  --sheet FundList `
  --output C:\path\to\monthly_returns.csv `
  --date-from 2022-01-01T00:00:00Z `
  --date-to 2026-03-31T23:59:59Z
```

Global source-type preference when your tenant is consistent:

```powershell
$env:CAISSA_BEARER_TOKEN = "paste-token-here"
python scripts/caissa_batch_monthly_returns.py `
  --input C:\path\to\funds.csv `
  --output C:\path\to\monthly_returns.csv `
  --date-from 2022-01-01T00:00:00Z `
  --date-to 2026-03-31T23:59:59Z `
  --preferred-source-types FundAccounting,FundHybrid
```

## Output files

The main output CSV includes:

- input row info
- matched fund id/code/name
- selected return source identifiers
- `date`
- `returnRate`

The issues CSV includes:

- ambiguous fund matches
- ambiguous return source matches
- missing return sources
- rows with no monthly returns in the requested date range
- API errors

## Notes

- `.xlsx` input requires `openpyxl`. CSV and TSV do not.
- Matching by `fundName` is exact, case-insensitive, and whitespace-normalized.
- The script intentionally stays strict when more than one return source is available unless you provide row-level hints or `--preferred-source-types`.
