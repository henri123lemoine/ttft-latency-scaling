PYTHON ?= python3
RSCRIPT ?= Rscript

.PHONY: validate results figures reproduce astra astra-results astra-figures exploratory exploratory-results sol-api sol-api-results sol-api-figures sol-api-validate

validate:
	$(PYTHON) scripts/validate_release.py
	$(PYTHON) scripts/export_exploratory_data.py --check

exploratory-results:
	$(PYTHON) scripts/export_exploratory_data.py

exploratory: exploratory-results
	$(PYTHON) scripts/export_exploratory_data.py --check

results: validate
	$(RSCRIPT) analysis/reproduce.R
	$(RSCRIPT) analysis/supporting_variance.R

figures:
	$(RSCRIPT) analysis/figures.R

astra-results: validate
	$(RSCRIPT) analysis/astra_api.R

astra-figures:
	$(RSCRIPT) analysis/figures.R --astra-api

astra: astra-results
	$(RSCRIPT) analysis/figures.R --astra-api

reproduce: results figures astra

sol-api-results:
	$(RSCRIPT) analysis/sol_api.R
	$(RSCRIPT) analysis/sol_api_validate.R

sol-api-figures:
	$(RSCRIPT) analysis/sol_api_figures.R

sol-api-validate:
	$(PYTHON) scripts/validate_sol_api.py

sol-api: sol-api-results sol-api-figures sol-api-validate
