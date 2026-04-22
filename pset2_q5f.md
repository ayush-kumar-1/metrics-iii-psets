# Prompt & Formulas Given to Gemini

Your goal is to write R code for a cross-fitted AIPW estimator. The following R packages are available `c("xgboost", "tidyverse", "fixest")`. No additional packages will need to be installed. The data you will be working with comes from NHANES 2007-2008. The ATE of interest is the effect of school mean participation on BMI. School mean participation is our treatment $A$, and is labeled as `School_Meal` in the data. BMI is our response and is labeled `BMI`. The following are are available covariates, stored as a vector called `covariates`. 


```r
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
```

You will be implementing an estimate for AIPW, which takes the following form. 

$$\hat \theta_{n, aug} = \frac{1}{n} \sum_{i=1}^n (\hat \mu_{n, 1} (W_i) - \hat \mu_{n, 0}(W_i) + A_i \frac{Y_i - \hat \mu_{n, 1}(W_i)}{\hat pi_n(W_i)} - (1 - A_i) \frac{Y_i - \hat \mu_{n, 0}(W_i)}{1 - \hat \pi_n(W_i)}$$

Note that this will require building three cross-fitted estimators: 
- $\hat \mu_{n, 1}(W_i)$ prediction of Y_i using only treated group for training
- $\hat \mu_{n, 1}(W_i)$ prediction of Y_i using only not treated group training
- $\hat \pi_n(W_i)$ propensity score estimate 

Estimate the outcomes using a linear regression, and the propensity score using a logistics regression. Compute the AIPW using K=5 folds. Report the estimate, the associated standard errors, and (\alpha = 0.05) CI for the ATE.


# Initial Code Ouput 

library(tidyverse)
library(fixest)

```r
# Assuming 'df' is your NHANES 2007-2008 dataframe
# data <- df 

# 1. Setup Variables
y_var <- "BMI"
a_var <- "School_Meal"
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
  mod_u1 <- feols(out_formula, data = train_data[train_data[[a_var]] == 1, ])
  # Model for Untreated (A=0)
  mod_u0 <- feols(out_formula, data = train_data[train_data[[a_var]] == 0, ])
  
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
    term2 = (School_Meal * (BMI - mu1_hat)) / pi_hat,
    term3 = ((1 - School_Meal) * (BMI - mu0_hat)) / (1 - pi_hat),
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
```

# Changes 

I had to change how the filtering was done inside the training loop, but otherwise the code was implemented well. This is slightly more complicated than it needs to be because we're doing everything "by hand" rather than using a package, but the overall logic was correct.
