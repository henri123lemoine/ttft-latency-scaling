#!/usr/bin/env Rscript
# Offline numerical provenance check. Does not modify any existing fit tables.
suppressPackageStartupMessages({library(MASS); library(jsonlite)})
source('analysis/sol_api_asymmetric_helpers.R')
expected<-read.csv('config/sol-api/historical_comparison_coefficients.csv')
old<-read.csv('outputs/tables/fit_coefficients.csv')
old<-subset(old,model=='GPT-5.6 Sol'&degree==2)
old$method<-ifelse(old$estimator=='Stochastic frontier','Frontier',old$estimator)
for(method in old$method) {
 actual<-old[old$method==method,c('alpha','beta','gamma')]
 ref<-expected[expected$model=='GPT-5.6 Sol'&expected$method==method,c('alpha','beta','gamma')]
 stopifnot(max(abs(as.numeric(actual)-as.numeric(ref)))<1e-10)
}
a<-read.csv('outputs/astra-api/request_observations.csv')
a$block<-factor(a$block)
stopifnot(nrow(a)==24,nlevels(a$block)==4)
f<-subset(read.csv('outputs/astra-api/fit_coefficients.csv'),degree==2)
ref<-subset(expected,model=='GPT-6 Astra'&method=='Student-t')
stopifnot(max(abs(unlist(f[c('alpha','beta','gamma')])-unlist(ref[c('alpha','beta','gamma')])))<1e-10)
rows<-list()
for(family in c('frontier_exponential','spike_exponential')) {
 f<-fit_asymmetric(a,family,2,fixed_sigma=estimate_clean_sigma(a))
 method<-if(family=='frontier_exponential')'Frontier' else 'Spike + contention'
 ref<-expected[expected$model=='GPT-6 Astra'&expected$method==method,]
 delta<-max(abs(unname(f$beta[1:3])-as.numeric(ref[c('alpha','beta','gamma')])))
 # Tolerance accommodates optimizer/libm differences, not materially changed fits.
 stopifnot(f$convergence==0,delta<1e-5)
 rows[[family]]<-data.frame(model='GPT-6 Astra',method=method,
  alpha=f$beta[1],beta=f$beta[2],gamma=f$beta[3],sigma=f$sigma,
  rate=f$rate,contention_probability=f$probability,nll=f$nll,
  maximum_absolute_coefficient_difference=delta)
}
write.csv(do.call(rbind,rows),'outputs/sol-api/astra_asymmetric_verification.csv',row.names=FALSE)
cat('Historical Sol coefficients unchanged; Astra asymmetric fits independently reproduced.\n')
