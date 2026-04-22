library(tidyverse)
library(fixest)
library(xgboost)

bmi = read_delim("../nhanes_bmi.csv", delim = ";", show_col_types = FALSE) %>%
  select(-"...1")

covariates = c(
  "age",
  "ChildSex",
  "black",
  "mexam",
  "pir200_plus",
  "WIC",
  "Food_Stamp",
  "fsdchbi",
  "AnyIns",
  "RefSex",
  "RefAge"
)

outcome_formula = reformulate(covariates, response = "BMI")

# (a) naive difference in mean estimator

cat("difference-in-means estimator")
feols(BMI ~ School_meal, data = bmi) %>% summary()

# (b) regression adjustment estimator

treated_model = feols(
  outcome_formula,
  data = filter(bmi, School_meal == 1)
)

not_treated_model = feols(
  outcome_formula,
  data = filter(bmi, School_meal == 0)
)

ols_regression_adjustment = bmi %>%
  mutate(
    ols_y1_hat = predict(treated_model, bmi),
    ols_y0_hat = predict(not_treated_model, bmi),
    ate = ols_y1_hat - ols_y0_hat
  ) %>%
  pull(ate) %>%
  mean(na.rm = TRUE)

c(ols_regression_adjustment = ols_regression_adjustment)

# (c) regression adjustment estimator using XGBoost

set.seed(123)

x = model.matrix(reformulate(covariates), data = bmi)[, -1, drop = FALSE]

xgb_params = list(
  objective = "reg:squarederror",
  eval_metric = "rmse",
  eta = 0.05,
  max_depth = 3,
  min_child_weight = 5,
  subsample = 0.8,
  colsample_bytree = 0.8
)

fit_xgb_outcome_model = function(treatment_value) {
  treatment_index = bmi$School_meal == treatment_value

  xgb.train(
    params = xgb_params,
    data = xgb.DMatrix(
      data = x[treatment_index, , drop = FALSE],
      label = bmi$BMI[treatment_index]
    ),
    nrounds = 300,
    verbose = 0
  )
}

xgb_treated_model = fit_xgb_outcome_model(1)
xgb_not_treated_model = fit_xgb_outcome_model(0)

x_all = xgb.DMatrix(data = x)

xgb_regression_adjustment = bmi %>%
  mutate(
    xgb_y1_hat = predict(xgb_treated_model, x_all),
    xgb_y0_hat = predict(xgb_not_treated_model, x_all),
    ate = xgb_y1_hat - xgb_y0_hat
  ) %>%
  pull(ate) %>%
  mean(na.rm = TRUE)

c(xgb_regression_adjustment = xgb_regression_adjustment)

# (d) IPW
prop_score_model = glm(reformulate(covariates, response="School_meal"), data=bmi, family="binomial")

theta_hat_ipw = bmi %>%
  mutate(
    pi_hat = predict(prop_score_model, bmi, type = "response"),
    ipw_i = (School_meal * BMI / pi_hat) - ((1 - School_meal) * BMI / (1 - pi_hat))
  ) %>%
  pull(ipw_i) %>%
  mean()

c(logit_ipw = theta_hat_ipw)
# (f) Code implemented for Cross-Fitted AIPW

# Assuming 'df' is your NHANES 2007-2008 dataframe
data <- bmi

# 1. Setup Variables
y_var <- "BMI"
a_var <- "School_meal"
covs  <- c("age", "ChildSex", "black", "mexam", "pir200_plus",
           "WIC", "Food_Stamp", "fsdchbi", "AnyIns", "RefSex", "RefAge")

# Construct formulas
out_formula <- as.formula(paste(y_var, "~", paste(covs, collapse = " + ")))
ps_formula  <- as.formula(paste(a_var, "~", paste(covs, collapse = " + ")))

# 2. Initialize Cross-Fitting
set.seed(123) # For reproducibility
K <- 5
n <- nrow(data)
data <- data %>%
  mutate(fold = sample(rep(1:K, length.out = n)))

# Containers for predictions
data$mu1_hat <- NA
data$mu0_hat <- NA
data$pi_hat  <- NA

# 3. Cross-Fitting Loop
for (k in 1:K) {
  # Define training and estimation sets
  train_idx <- which(data$fold != k)
  test_idx  <- which(data$fold == k)

  train_data <- data[train_idx, ]
  test_data  <- data[test_idx, ]

  # --- Step A: Outcome Models (Linear Regression) ---
  # Model for Treated (A=1)
  mod_u1 <- feols(out_formula, data = filter(train_data, !!sym(a_var) == 1))
  # Model for Untreated (A=0)
  mod_u0 <- feols(out_formula, data = filter(train_data, !!sym(a_var) == 0))

  # --- Step B: Propensity Score Model (Logistic Regression) ---
  mod_pi <- feglm(ps_formula, data = train_data, family = "logit")

  # --- Step C: Generate Predictions for the Test Fold ---
  data$mu1_hat[test_idx] <- predict(mod_u1, newdata = test_data)
  data$mu0_hat[test_idx] <- predict(mod_u0, newdata = test_data)
  data$pi_hat[test_idx]  <- predict(mod_pi, newdata = test_data, type = "response")
}

# 4. Compute AIPW Estimate
# Standard practice: clip propensity scores to avoid extreme weights
data <- data %>%
  mutate(pi_hat = pmax(pmin(pi_hat, 0.99), 0.01)) %>%
  mutate(
    # Individual components of the AIPW formula
    term1 = mu1_hat - mu0_hat,
    term2 = (School_meal * (BMI - mu1_hat)) / pi_hat,
    term3 = ((1 - School_meal) * (BMI - mu0_hat)) / (1 - pi_hat),
    phi   = term1 + term2 - term3
  )

# 5. Final Statistics
ate_estimate <- mean(data$phi)
se_estimate  <- sd(data$phi) / sqrt(n)
alpha <- 0.05
z_crit <- qnorm(1 - alpha/2)

ci_low <- ate_estimate - z_crit * se_estimate
ci_high <- ate_estimate + z_crit * se_estimate

# --- Results Output ---
cat("AIPW ATE Results (K=5 Cross-fitting):\n")
cat("------------------------------------\n")
cat(sprintf("Estimate:      %.4f\n", ate_estimate))
cat(sprintf("Std. Error:    %.4f\n", se_estimate))
cat(sprintf("95%% CI:        [%.4f, %.4f]\n", ci_low, ci_high))
