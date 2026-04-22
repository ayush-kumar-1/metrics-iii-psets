library(tidyverse)
library(fixest)
library(haven)

wages = read_stata("../wage2.dta") %>%
  mutate(exper_bin = exper > 10) %>%
  select(
    wage,
    exper_bin,
    urban,
    IQ,
    educ
  )

wages_rural = wages %>% filter(urban == 0)
wages_urban = wages %>% filter(urban == 1)

urban_models = list(
  "(a)" = feols(log(wage) ~ exper_bin, data = wages_urban),
  "(b)" = feols(log(wage) ~ exper_bin | IQ, data = wages_urban),
  "(c)" = feols(log(wage) ~ exper_bin | IQ ^ educ , data = wages_urban),
  "(d)" = feols(log(wage) ~ exper_bin * factor(IQ), data = wages_urban),
  "(e)" = feols(log(wage) ~ exper_bin * factor(IQ):factor(educ), data = wages_urban)
)

rural_models = list(
  "(a)" = feols(log(wage) ~ exper_bin, data = wages_rural),
  "(b)" = feols(log(wage) ~ exper_bin | IQ, data = wages_rural),
  "(c)" = feols(log(wage) ~ exper_bin | IQ ^ educ , data = wages_rural),
  "(d)" = feols(log(wage) ~ exper_bin * factor(IQ), data = wages_rural),
  "(e)" = feols(log(wage) ~ exper_bin * factor(IQ):factor(educ), data = wages_rural)
)

setFixest_dict("exper_binTRUE" = "Experience >10", "log(wage)" = "Wage (Log)")


etable(urban_models,
  tex = TRUE,
  replace = TRUE,
  title = "Urban Residents",
  label = "tab:wage_reg_ruban",
  fitstat = ~ n + r2,
  drop = c("Constant", "IQ"),
  file = "pset1_wages_urban.tex",
  style.tex = style.tex("aer")
)

etable(rural_models,
  tex = TRUE,
  replace = TRUE,
  title = "Rural Residents",
  label = "tab:wage_reg_rural",
  fitstat = ~ n + r2,
  drop = c("Constant", "IQ"),
  file = "pset1_wages_rural.tex",
  style.tex = style.tex("aer")
)
