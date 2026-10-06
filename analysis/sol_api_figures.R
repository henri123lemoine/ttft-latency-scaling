#!/usr/bin/env Rscript
# API-only 2x2 comparison; reuse saved authoritative fits, never call a provider.
suppressPackageStartupMessages(library(ggplot2))
suppressPackageStartupMessages(library(jsonlite))
out <- 'figures/sol-api'
tables <- 'outputs/sol-api/comparison'
dir.create(out,recursive=TRUE,showWarnings=FALSE)
dir.create(tables,recursive=TRUE,showWarnings=FALSE)
labels <- c('GPT-5.6 Sol','GPT-6 Astra','GPT-6 Sol','GPT-6.1 Sol')
read_measured <- function(path) {
 records<-lapply(readLines(path),fromJSON,simplifyVector=FALSE)
 Filter(function(r)identical(r$type,'sample')&&identical(r$kind,'measured')&&isTRUE(r$valid),records)
}
astra_paths<-c('data/raw/astra-api/20260909T123307Z-1c49feec.jsonl',
 'data/raw/astra-api/20260909T124315Z-c70b34b7.jsonl')
old_astra<-do.call(rbind,lapply(astra_paths,function(path)
 do.call(rbind,lapply(read_measured(path),function(r)data.frame(model='GPT-6 Astra',
  tokens=r$total_input_tokens,ttft=r$ttft_ns/1e9,session=basename(path),
  block=paste0(basename(path),':',r$repetition))))))
old_sol<-do.call(rbind,lapply(read_measured('data/raw/final/20260814T140715Z-bee825d8.jsonl'),
 function(r)data.frame(model='GPT-5.6 Sol',tokens=r$total_input_tokens,ttft=r$ttft_ns/1e9,
 session=r$session,block=as.character(r$repetition+1))))
old_sol<-old_sol[order(as.integer(old_sol$block),old_sol$tokens),]
old<-rbind(old_astra,old_sol)
new<-read.csv('outputs/sol-api/observations.csv')
stopifnot(nrow(old)==54,all(new$valid),all(new$used_in_fit),nrow(new)==60)
points<-rbind(old,data.frame(model=ifelse(new$model=='gpt-6-sol','GPT-6 Sol','GPT-6.1 Sol'),
 tokens=new$x*1e6,ttft=new$y,session=paste0('2026-10-06:',new$model),block=as.character(new$block)))
counts<-table(factor(points$model,levels=labels))
stopifnot(identical(as.integer(counts),c(30L,24L,30L,30L)))
# Immutable historical fitted coefficients: independently verified by sol_api_validate.R.
# In particular, the original 5.6 fits used nominal x; do not refit/change headline fits.
coefficients<-read.csv('config/sol-api/historical_comparison_coefficients.csv')
nc<-read.csv('outputs/sol-api/fit_coefficients.csv')
nc<-nc[nc$estimator!='student_linear',]
method_map<-c(student_quadratic='Student-t',frontier_exponential='Frontier',spike_exponential='Spike + contention')
coefficients<-rbind(coefficients,data.frame(model=ifelse(nc$model=='gpt-6-sol','GPT-6 Sol','GPT-6.1 Sol'),
 alpha=nc$alpha,beta=nc$beta,gamma=nc$gamma,method=unname(method_map[nc$estimator])))
stopifnot(nrow(coefficients)==12,all(table(coefficients$model,coefficients$method)==1))
# Optional literal minimum-point quadratic, matching the earlier 2x2 supplement.
# Descriptive OLS across minima, no block effects or confidence intervals.
minima <- do.call(rbind,lapply(labels,function(m){
  d<-subset(points,model==m)
  p<-do.call(rbind,lapply(split(d,d$tokens),function(z)z[which.min(z$ttft),]))
  x<-p$tokens/1e6
  f<-lm(p$ttft~x+I(x^2))
  coefficients <<- rbind(coefficients,data.frame(model=m,alpha=unname(coef(f)[1]),
    beta=unname(coef(f)[2]),gamma=unname(coef(f)[3]),method='Floor (minimum)'))
  p
}))
curves <- do.call(rbind,lapply(seq_len(nrow(coefficients)),function(i){
  f<-coefficients[i,]; p<-subset(points,model==f$model)
  x<-seq(min(p$tokens),max(p$tokens),length.out=300)/1e6
  data.frame(model=f$model,method=f$method,tokens=x*1e6,ttft=f$alpha+f$beta*x+f$gamma*x*x)
}))
stopifnot(nrow(curves)==4800,all(points$ttft>=0&points$ttft<35),all(points$tokens<950000))
render <- function(methods,stem,single=FALSE,titled=FALSE) {
  # ggplotGrob can initialize a default device; never leave an unrelated Rplots.pdf.
  grDevices::pdf(file=NULL)
  on.exit(grDevices::dev.off(),add=TRUE)
  selected <- curves[curves$method %in% methods,]
  colors<-c('Student-t'='#276FBF','Frontier'='#D97706','Spike + contention'='#2E8B57','Floor (minimum)'='#7C3AED')
  if(single)colors['Student-t']<-'#D97706'
  styles<-c('Student-t'='solid','Frontier'='dashed','Spike + contention'='dotted','Floor (minimum)'='dotdash')
  base<-ggplot()+
    geom_point(data=points,aes(tokens/1000,ttft,shape='Raw request'),color='#4B5563',alpha=.34,
      size=sqrt(24)*25.4/72.27,stroke=0)+
    geom_line(data=selected,aes(tokens/1000,ttft,color=method,linetype=method),linewidth=2.4*25.4/72.27)+
    scale_shape_manual(NULL,values=c('Raw request'=16))+
    scale_color_manual(NULL,breaks=methods,values=colors)+
    scale_linetype_manual(NULL,breaks=methods,values=styles)+
    scale_x_continuous(breaks=c(0,300,600,900),limits=c(0,950),expand=c(0,0))+
    scale_y_continuous(breaks=c(0,10,20,30),limits=c(0,35),expand=c(0,0))+
    labs(x='Input context (thousand tokens)',y='Time to first token (s)')+
    guides(shape=guide_legend(order=1),color=guide_legend(order=2),linetype=guide_legend(order=2))+
    theme_classic(base_size=11)+
    theme(plot.title=element_text(size=13.5,face='bold',hjust=0),
      panel.grid.major.y=element_line(color=scales::alpha('#4B5563',.14),linewidth=.7*25.4/72.27),
      axis.line=element_line(linewidth=.8*25.4/72.27),axis.ticks=element_line(linewidth=.8*25.4/72.27),
      axis.ticks.length=grid::unit(3.5,'pt'),axis.text=element_text(size=10),
      legend.position='bottom',legend.box='horizontal',legend.text=element_text(size=10.2),
      legend.key.width=grid::unit(26,'pt'),plot.margin=margin(12,16,8,12))
  g<-ggplotGrob(base); indices<-which(grepl('^guide-box',g$layout$name))
  index<-indices[vapply(g$grobs[indices],function(x)inherits(x,'gtable'),logical(1))][1]
  legend<-g$grobs[[index]]
  panels<-lapply(seq_along(labels),function(i){
    m<-labels[i]; p<-base
    p$layers[[1]]$data<-subset(points,model==m)
    p$layers[[2]]$data<-subset(selected,model==m)
    if('Floor (minimum)' %in% methods)p<-p+geom_point(data=subset(minima,model==m),
      aes(tokens/1000,ttft),color='#7C3AED',size=2,show.legend=FALSE)
    p<-p+labs(title=m)+theme(legend.position='none')
    grid::grobTree(ggplotGrob(p),vp=grid::viewport(x=if(i%%2==1).25 else .75,
      y=if(i<=2).765 else .305,width=.5,height=.46))
  })
  figure<-do.call(grid::grobTree,c(panels,list(grid::grobTree(legend,
    vp=grid::viewport(x=.5,y=.0375,width=1,height=.075)))))
  height<-9.6
  if(titled) {
    # Add a header above the original 9.6-inch figure without shrinking its panels.
    height<-10.6
    body<-grid::grobTree(figure,vp=grid::viewport(x=.5,y=4.8/height,width=1,height=9.6/height))
    figure<-grid::grobTree(body,
      grid::textGrob('GPT-6.1 Sol\u2019s TTFT scales more slowly than earlier Sol models',
        x=.0475,y=1-.28/height,just=c('left','top'),
        gp=grid::gpar(fontsize=13.5,fontface='bold',col='#111827')),
      grid::textGrob(paste0('Each dot is one request; curves show three quadratic-capable estimators and a fit to the\n',
                            'minimum latency at each input length.'),
        x=.0475,y=1-.61/height,just=c('left','top'),
        gp=grid::gpar(fontsize=11,col='#556568',lineheight=1.25)))
  }
  for(ext in c('png','svg','pdf'))ggsave(file.path(out,paste0(stem,'.',ext)),figure,
    device=if(ext=='svg')grDevices::svg else if(ext=='pdf')grDevices::cairo_pdf else ext,
    width=12.2,height=height,dpi=240,bg='white')
}
render(c('Student-t','Frontier','Spike + contention','Floor (minimum)'),
       'four_model_api_robustness_with_minimum_floor_2x2_titled',titled=TRUE)
write.csv(points,file.path(tables,'four_model_api_observations.csv'),row.names=FALSE)
write.csv(coefficients,file.path(tables,'four_model_api_fit_coefficients.csv'),row.names=FALSE)
write.csv(curves,file.path(tables,'four_model_api_fit_curves.csv'),row.names=FALSE)
write.csv(minima,file.path(tables,'four_model_api_minimum_points.csv'),row.names=FALSE)
cat('Saved API-only 2x2 figures: 114 observations; no authoritative fits changed.\n')
