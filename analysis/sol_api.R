#!/usr/bin/env Rscript
# Offline analysis only. Independent API sessions; no paired-block inference.
suppressPackageStartupMessages({library(jsonlite); library(MASS); library(ggplot2)})
args <- commandArgs(trailingOnly=TRUE)
input <- if(length(args))args[1] else 'data/raw/sol-api/20261006-sol-shared.jsonl'
out <- if(length(args)>1)args[2] else 'outputs/sol-api'
dir.create(out,recursive=TRUE,showWarnings=FALSE)
definitions <- function(path) {
  e<-new.env(parent=globalenv())
  for(z in parse(path))if(is.call(z)&&identical(z[[1]],as.name('<-'))&&is.symbol(z[[2]])&&
    is.call(z[[3]])&&identical(z[[3]][[1]],as.name('function')))eval(z,e)
  e
}
st<-definitions('analysis/sol_api_student_helpers.R')
asym<-definitions('analysis/sol_api_asymmetric_helpers.R')
records<-lapply(readLines(input),fromJSON,simplifyVector=FALSE)
raw<-Filter(function(r)identical(r$type,'sample')&&identical(r$kind,'measured'),records)
num<-function(x)if(is.null(x))NA_real_ else x
d<-do.call(rbind,lapply(raw,function(r)data.frame(model=r$model,block=r$block,target=r$target_tokens,
  x=num(r$total_input_tokens)/1e6,y=num(r$ttft_ns)/1e9,valid=r$valid,
  timestamp=r$request_started_at,cache_read=num(r$cache_read_tokens),cache_write=num(r$cache_write_tokens),
  reasoning=num(r$reasoning_tokens),cost=num(r$estimated_cost_usd))))
d$used_in_fit<-FALSE
for(m in unique(d$model))for(b in unique(d$block[d$model==m])) {
  i<-which(d$model==m&d$block==b)
  if(length(i)==6&&all(d$valid[i])&&length(unique(d$target[i]))==6)d$used_in_fit[i]<-TRUE
}
write.csv(d,file.path(out,'observations.csv'),row.names=FALSE)
fits<-list(); evidence<-list(); coeffs<-list(); curves<-list(); draws_all<-list(); asym_draws<-list(); ae<-list()
B<-as.integer(Sys.getenv('TTFT_SHAPE_BOOTSTRAPS','5000'))
BA<-as.integer(Sys.getenv('ASYMMETRIC_BOOTSTRAPS','200'))
for(m in unique(d$model)) {
  z<-subset(d,model==m&used_in_fit); z$block<-factor(z$block)
  if(nlevels(z$block)<3)next
  lin<-st$fit_student(z,1); quad<-st$fit_student(z,2)
  stopifnot(lin$convergence==0,quad$convergence==0)
  set.seed(if(m=='gpt-6-sol')20261006 else 20261007)
  draws<-replicate(B,tryCatch(suppressWarnings(st$huber_quadratic(st$resample_blocks(z))),error=function(e)NA_real_))
  ci<-quantile(draws,c(.025,.975),na.rm=TRUE)
  lr<-2*(quad$log_likelihood-lin$log_likelihood)
  evidence[[m]]<-data.frame(model=m,n=nrow(z),blocks=nlevels(z$block),
    alpha=unname(quad$beta[1]),beta=unname(quad$beta['x']),gamma=unname(quad$beta['I(x^2)']),
    sigma=quad$sigma,LR=lr,approximate_LR_p_chisq1=pchisq(max(lr,0),1,lower.tail=FALSE),
    linear_AICc=lin$aicc,quadratic_AICc=quad$aicc,
    huber_gamma=st$huber_quadratic(z),huber_gamma_low=ci[1],huber_gamma_high=ci[2],
    huber_fraction_positive=mean(draws>0,na.rm=TRUE),bootstrap_success=sum(is.finite(draws)),bootstrap_requested=B)
  draws_all[[m]]<-data.frame(model=m,replicate=seq_along(draws),gamma=draws)
  sigma<-asym$estimate_clean_sigma(z)
  mf<-list(student_linear=lin,student_quadratic=quad)
  for(family in c('frontier_exponential','spike_exponential')) {
    f<-asym$fit_asymmetric(z,family,2,fixed_sigma=sigma)
    half<-asym$fit_asymmetric(z,family,2,fixed_sigma=sigma*.5)
    twice<-asym$fit_asymmetric(z,family,2,fixed_sigma=sigma*2)
    stopifnot(f$convergence==0)
    set.seed(if(m=='gpt-6-sol')20261006 else 20261007)
    ad<-lapply(seq_len(BA),function(i){
      zb<-asym$resample_blocks(z)
      ff<-tryCatch(suppressWarnings(asym$fit_asymmetric(zb,family,2,fixed_sigma=asym$estimate_clean_sigma(zb))),error=function(e)NULL)
      data.frame(model=m,family=family,replicate=i,gamma=if(is.null(ff))NA_real_ else unname(ff$beta['I(x^2)']),
                 convergence=if(is.null(ff))NA_integer_ else ff$convergence)
    })
    ad<-do.call(rbind,ad); good<-is.finite(ad$gamma)&!is.na(ad$convergence)&ad$convergence==0
    aci<-if(any(good))quantile(ad$gamma[good],c(.025,.975)) else c(NA,NA)
    ae[[paste(m,family)]]<-data.frame(model=m,family=family,gamma=unname(f$beta['I(x^2)']),
      gamma_low=aci[1],gamma_high=aci[2],bootstrap_success=sum(good),bootstrap_requested=BA,
      gamma_half_sigma=unname(half$beta['I(x^2)']),gamma_double_sigma=unname(twice$beta['I(x^2)']))
    asym_draws[[paste(m,family)]]<-ad
    mf[[family]]<-f
  }
  fits[[m]]<-mf
  grid<-seq(min(z$x),max(z$x),length.out=300)
  for(name in names(mf)) {
    f<-mf[[name]]; gamma<-if('I(x^2)' %in% names(f$beta))unname(f$beta['I(x^2)']) else 0
    coeffs[[paste(m,name)]]<-data.frame(model=m,estimator=name,alpha=unname(f$beta[1]),
      beta=unname(f$beta['x']),gamma=gamma,sigma=f$sigma,
      rate=if(is.null(f$rate))NA_real_ else f$rate,
      contention_probability=if(is.null(f$probability))NA_real_ else f$probability,
      nll=if(is.null(f$nll))-f$log_likelihood else f$nll)
    curves[[paste(m,name)]]<-data.frame(model=m,estimator=name,x=grid,
      y=unname(f$beta[1])+unname(f$beta['x'])*grid+gamma*grid^2)
  }
  cat(m,'analysis complete\n')
}
write.csv(do.call(rbind,evidence),file.path(out,'evidence.csv'),row.names=FALSE)
write.csv(do.call(rbind,coeffs),file.path(out,'fit_coefficients.csv'),row.names=FALSE)
write.csv(do.call(rbind,draws_all),file.path(out,'huber_bootstrap.csv'),row.names=FALSE)
write.csv(do.call(rbind,ae),file.path(out,'asymmetric_evidence.csv'),row.names=FALSE)
write.csv(do.call(rbind,asym_draws),file.path(out,'asymmetric_bootstrap.csv'),row.names=FALSE)
export_fits<-lapply(fits,function(fs)lapply(fs,function(f){f$beta<-as.list(f$beta);f}))
write_json(export_fits,file.path(out,'fits.json'),pretty=TRUE,auto_unbox=TRUE,digits=16)
block_rows<-list()
for(m in names(fits))for(est in names(fits[[m]])) {
 f<-fits[[m]][[est]]; v<-unname(f$beta[grep('^block',names(f$beta))])
 block_rows[[paste(m,est)]]<-data.frame(model=m,estimator=est,block=f$block_levels,
  offset_seconds=c(v,-sum(v)))
}
write.csv(do.call(rbind,block_rows),file.path(out,'fit_block_effects.csv'),row.names=FALSE)
curves<-do.call(rbind,curves)
write.csv(curves,file.path(out,'fit_curves.csv'),row.names=FALSE)
cat('Saved independent Sol API analyses.\n')
