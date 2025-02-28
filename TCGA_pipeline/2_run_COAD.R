
library(data.table)
library(scales)
library(stringr)
library(e1071)
library(ggplot2)
library(MASS)
library(gridExtra)
library(quantreg)
library(quadprog)
library(EMeth)
library(cowplot)
library(ggpubr)
theme_set(theme_classic2())

# the raw data of DNA metylation is too large to be kept in gitHub
# here is the local path for DNA methylation data
# path.data = "C:/Users/Hanyu/Downloads/Processed/"
path.data = "~/research/TCGA/COAD/_data2"

# ------------------------------------------------------------
# read in pure cell type data
# ------------------------------------------------------------

path.ref = "../cell_type_specific_reference/data"

info = fread(file.path(path.ref, "methylation_pure_ct_info.txt.gz"))
dim(info)
info[1:2,]

fnm = file.path(path.ref, "methylation_pure_ct_rmPC2_data_signif4.txt.gz")
dat = fread(fnm)
dim(dat)
dat[1:2,1:5]

sam = fread(file.path(path.ref, "methylation_pure_ct_sample.txt"))
dim(sam)
sam[1:2,]

table(names(dat) == sam$id)

dat = data.matrix(dat)
table(sam$label)
rownames(dat) = info$ID

# ------------------------------------------------------------
# read DNA methylation data
# ------------------------------------------------------------

datM = fread(file.path(path.data, "methylation_betaValue.txt"))
dim(datM)
datM[1:2, 1:5]

infoM = fread(file.path(path.ref, "methylation_info.txt"))
dim(infoM)
names(infoM)
infoM[1:2, 1:5]
table(infoM$CHR)

table(datM$id == infoM$Name)

datM = data.matrix(datM[,-1])
rownames(datM) = infoM$Name
dim(datM)
datM[1:2, 1:5]

# ------------------------------------------------------------
# take intersection of CpG probes between purified data and 
# bulk tumor samples
# ------------------------------------------------------------

table(info$ID == info$Name)
cpgs = intersect(info$ID, infoM$Name)
length(cpgs)

mat1  = match(cpgs, infoM$Name)
datM  = datM[mat1,]
infoM = infoM[mat1,]

dim(datM)
datM[1:2, 1:5]

dim(infoM)
infoM[1:2, 1:5]

mat2 = match(cpgs, info$ID)
dat  = dat[mat2,]
info = info[mat2,]

dim(dat)
dat[1:2, 1:5]

dim(info)
info[1:2, 1:5]

# ------------------------------------------------------------
# read in probes to be used
# ------------------------------------------------------------

load(file.path(path.ref, "ref_966probes.RData"))
ls()
length(probe2use)
length(unique(probe2use))

table(probe2use %in% rownames(datM))
table(probe2use %in% rownames(dat))

X  = dat[match(probe2use, rownames(dat)),]
dim(X)
X[1:2,1:5]

dim(sam)
table(sam$id == colnames(X))
table(sam$label)
cellTypes = unique(sam$label)

# ------------------------------------------------------------
# read tumor purity from pan cancer study, and compare it 
# with the purity estimates from an earlier study
# ------------------------------------------------------------

dir0 = "TCGA_results/clinical_data/"

emInfo = fread(paste0(dir0, "patient_coad_M_info_hyperMeth.txt"))
dim(emInfo)
emInfo[1, ]

purity = fread(paste0(dir0, "TCGA_mastercalls.abs_tables_JSedit.fixed.txt"))
dim(purity)
purity[1, ]

emInfo$array = substring(emInfo$methylation_barcode, 1, 15)
table(emInfo$array %in% purity$array)
table(purity$array %in% emInfo$array)

emInfo = merge(emInfo, purity, by="array")
dim(emInfo)
emInfo[1, ]

summary(emInfo$abs_purity)
summary(emInfo$purity)
cor(emInfo$abs_purity, emInfo$purity, use="pair")

# ------------------------------------------------------------
# extract methylation data from tumor samples
# ------------------------------------------------------------

ys = datM[match(rownames(X), rownames(datM)),]
dim(ys)
ys[1:2,1:5]

table(colnames(ys) %in% emInfo$patient_id)
patient_id_2use = intersect(colnames(ys), emInfo$patient_id)

ys = ys[,match(patient_id_2use,colnames(ys))]
emInfo = emInfo[match(patient_id_2use,emInfo$patient_id),]

dim(ys)
dim(emInfo)

stopifnot(all(colnames(ys) == emInfo$patient_id))
emInfo$patient_id[1:5]

ys_na      = which(apply(is.na(ys),2,any))
eta_abs_na = which(is.na(emInfo$purity))

any.na = union(ys_na,eta_abs_na)
any.na

ys = ys[,-any.na]
emInfo = emInfo[-any.na,]

dim(ys)
ys[1:2,1:5]

dim(emInfo)
emInfo[1:2,]

table(colnames(ys) == emInfo$patient_id)

#-------------------------------------------------------------
# Estimate Mean Matrix mu
#-------------------------------------------------------------

mu = matrix(NA, nrow = dim(X)[1], ncol = length(cellTypes))
s2 = matrix(NA, nrow = dim(X)[1], ncol = length(cellTypes))

row.names(mu) = row.names(s2) = rownames(X)
colnames(mu)  = colnames(s2)  = cellTypes

for(ct in cellTypes){
  sam.ct = unlist(sam[which(sam[,2]==ct),1])
  dat.ct = X[,sam.ct]
  mu[,ct] = rowMeans(dat.ct,na.rm=TRUE)
  s2[,ct] = apply(dat.ct,1,sd,na.rm = TRUE)^2
}

#----------------------------------------------------------------------
# Read Estimation from Expression Data, take intersection of the 
# samples with cell type proportion estimates from expression or 
# DNA methylation
#----------------------------------------------------------------------

fnm = '_cibersortx_results/CIBERSORTx_COAD_Adjusted.txt'
est_expr = fread(fnm)
dim(est_expr)
est_expr[1:2,]

samname  = substr(est_expr$Mixture, 9, 12)
length(samname)
samname[1:5]

est_expr = data.matrix(est_expr[,-1])
rownames(est_expr) = samname
dim(est_expr)
est_expr[1:2,]

com_sample = intersect(rownames(est_expr), colnames(ys))
length(com_sample)

est_expr = est_expr[match(com_sample,rownames(est_expr)),]
dim(est_expr)
est_expr[1:2,]

ys     = ys[,match(com_sample,colnames(ys))]
emInfo = emInfo[match(com_sample, emInfo$patient_id),]

dim(ys)
ys[1:2,1:4]

dim(emInfo)
emInfo[1:2,]

table(colnames(ys) == emInfo$patient_id)
table(colnames(ys) == rownames(est_expr))
table(rownames(ys) == rownames(mu))

#----------------------------------------------------------------------
# collapse cell types from expression data into fewer cell types
#----------------------------------------------------------------------

deconv_expr = matrix(NA, nrow = nrow(est_expr),ncol = length(cellTypes))
colnames(deconv_expr) = cellTypes 
rownames(deconv_expr) = rownames(est_expr)
colnames(est_expr)

other = rowSums(est_expr[,c(10,19,20,21)])
deconv_expr[,"B"]    = rowSums(est_expr[,1:3])/0.4
deconv_expr[,"CD4T"] = rowSums(est_expr[,5:8])/0.4
deconv_expr[,"CD8T"] = as.matrix(est_expr[,4])/0.4
deconv_expr[,"Treg"] = as.matrix(est_expr[,9])/0.4
deconv_expr[,"NK"] = rowSums(est_expr[,11:12])/0.42
deconv_expr[,"Monocyte"] = rowSums(est_expr[,13:18])/1.40
deconv_expr[,"Neutrophil"] = as.matrix(est_expr[,22])/0.15
deconv_expr = deconv_expr / rowSums(deconv_expr)

dim(deconv_expr)
deconv_expr[1:2,]

#---------------------------------------------------------------------
# Compare results with different methods and with expression data
#---------------------------------------------------------------------

eta = emInfo$purity
summary(eta)
eta[which(eta > 0.99)] = 0.99

temp = rownames(deconv_expr)
deconv_expr = diag(1-eta) %*% deconv_expr
rownames(deconv_expr) = temp

mu[mu < 0.05] = 0.05
mu[mu > 0.95] = 0.95

penalty = dim(ys)[1]*(10^seq(-2,1,1)) 

methods = c("EMeth","svr","ls","rls","qp")
rho     = array(data = NA, dim = c(ncol(ys), length(cellTypes), length(methods)),
                dimnames = list(colnames(ys), cellTypes, methods))

alpha   = rep(1/length(cellTypes), length(cellTypes))
simsize = ncol(ys)

C = c(0.1,1/sqrt(10),1,sqrt(10),10)

for(j in 1:ncol(ys)){
  if(j %% 10 == 0){ cat(j, date(), "\n") }
  y    = ys[,j]
  X    = as.data.frame(mu)
  Xmat = mu
  
  cv_svr = rep(0,5)
  svrmodel1       = svm(y~., data = X, kernel='linear', cost=0.1, cross=5)
  cv_svr[1]       = mean(svrmodel1$MSE)
  svrmodel2       = svm(y~., data = X, kernel='linear', cost=1/sqrt(10), cross=5)
  cv_svr[2]       = mean(svrmodel2$MSE)
  svrmodel3       = svm(y~., data = X, kernel='linear', cost=1, cross=5)
  cv_svr[3]       = mean(svrmodel2$MSE)
  svrmodel4       = svm(y~., data = X, kernel='linear', cost=sqrt(10), cross=5)
  cv_svr[4]       = mean(svrmodel2$MSE)
  svrmodel5       = svm(y~., data = X, kernel='linear', cost=10, cross=5)
  cv_svr[5]       = mean(svrmodel5$MSE)
  best_svr        = which.min(cv_svr)
  svrmodel        = svm(y~., data = X, kernel='linear', cost=C[best_svr])
  temp            = (t(svrmodel$coefs) %*% svrmodel$SV)
  temp[temp < 0]  = 0
  rho[j,,'svr']   = (1-eta[j])*temp/sum(temp)
  
  temp            = lm(y ~ .-1,data = X)$coefficients
  temp[temp < 0]  = 0
  rho[j,,'ls']    = (1-eta[j])*temp/sum(temp)
  
  temp            = rlm(y ~ .-1,data = X)$coefficients
  temp[temp < 0]  = 0
  rho[j,,'rls']   = (1-eta[j])*temp/sum(temp)
  
  A = rbind(diag(rep(1,length(cellTypes))),rep(-1,length(cellTypes)))
  b = c(rep(0,length(cellTypes)),-1+eta[j])
  D = t(Xmat) %*% Xmat
  d = t(t(Xmat) %*% y)
  rho[j,,'qp']   = (solve.QP(D,d,t(A),b)$solution)
}

print('EMeth')
hundrediter = cv.emeth(ys, eta, mu, aber = TRUE, V='c', init = 'default',
                       family = 'normal', nu = penalty, folds = 5, 
                       maxiter = 50, verbose = TRUE)

names(hundrediter)
summary(hundrediter[[1]]$pi_a)

rho[,,'EMeth'] = hundrediter[[1]]$rho

dim(rho[,,'EMeth'])
rho[1:2,,'EMeth']

EM_purity = 1 - rowSums(rho[,,'EMeth'])
summary(EM_purity - eta)

#---------------------------------------------------------------------
# save the results
#---------------------------------------------------------------------

dim(rho)
rho[1,,]
dimnames(rho)

dim(deconv_expr)
deconv_expr[1:2,]

save(rho, file = 'TCGA_results/deconv_methy_COAD.RData')
save(deconv_expr, file = 'TCGA_results/deconv_expr_COAD.RData')

#---------------------------------------------------------------------
# calculate summary statistics
#---------------------------------------------------------------------

# load('TCGA_results/deconv_methy_COAD.RData')
# load('TCGA_results/deconv_expr_COAD.RData')

utypes = intersect(cellTypes,colnames(deconv_expr))
utypes

methods = c("EMeth","svr","ls","rls","qp")

cormat = matrix(NA, nrow = length(utypes), ncol = length(methods))
colnames(cormat) = methods
rownames(cormat) = utypes

err = rss = cormat

for(i in 1:length(utypes)){
  cormat[i,] = sapply(1:length(methods), FUN = function(j){
    cor(rho[,utypes[i],methods[j]], deconv_expr[,utypes[i]])
  })
  err[i,] = sapply(1:length(methods), FUN = function(j){
    sqrt(mean((rho[,utypes[i],methods[j]] - deconv_expr[,utypes[i]])^2))
  }) 
  rss[i,] = sapply(1:length(methods), FUN = function(j){
    temp = lm(deconv_expr[,utypes[i]] ~ rho[,utypes[i],methods[j]])
    return(sum(temp$residuals^2))
  })
}

#---------------------------------------------------------------------
# scatter plots of cell type proportion estimates by 
# DNA methylation vs. gene expression
#---------------------------------------------------------------------

for(i in 1:length(utypes)){
  
  pdf(sprintf('_figures_COAD/COAD_expr_vs_methy_%s.pdf',utypes[i]), 
      width=6, height=7.5)
  
  plist = list()
  
  plist = lapply(1:length(methods), FUN = function(j){
    tempdata = cbind(rho[,utypes[i],methods[j]],deconv_expr[,utypes[i]],eta)
    colnames(tempdata) = c("methylation","expression","eta")
    newplot = ggplot(data = as.data.frame(tempdata), 
                      aes(x=methylation, y=expression, color=eta)) + 
      xlim(0,0.3) + ylim(0,0.3) + geom_point(size=0.8) + 
      geom_abline(intercept = 0,slope = 1) + 
      scale_color_gradient2(limit = c(0,1), low = "blue", high = "red", 
                           mid = "cadetblue1", midpoint = 0.5) + 
      ggtitle(sprintf('%s on %s',methods[j],utypes[i]))
  })
  
  grid.arrange(grobs = plist,ncol=2)
  dev.off()
  
  fnm = sprintf('_figures_COAD/COAD_plot_list_%s.RData', utypes[i])
  save(plist, file = fnm)
  
}

#---------------------------------------------------------------------
# Summarize correlation and RMSE
#---------------------------------------------------------------------

pdf('_figures_COAD/COAD_box_plot_correlation.pdf', width=4.5, height=3.5)
tempdata = melt(as.data.table(cormat))
colnames(tempdata) = c('Methods','Correlation')
tempdata$cellType = rep(utypes,5)
p1_cor = ggplot(tempdata,aes(x=Methods,y=Correlation)) + geom_boxplot() +
  geom_point(size = 2,aes(colour = cellType)) + theme_cowplot() + 
  ggtitle('Correlation for COAD')
print(p1_cor)
dev.off()


pdf('_figures_COAD/COAD_box_plot_RMSE.pdf', width=4.5, height=3.5)
tempdata = melt(as.data.table(err))
colnames(tempdata) = c('Methods','RMSE')
tempdata$cellType = rep(utypes,5)
p2_RMSE = ggplot(tempdata,aes(x=Methods,y=RMSE)) + geom_boxplot() +
  geom_point(size = 2,aes(colour = cellType)) + theme_cowplot() + 
  ggtitle('RMSE for COAD')
print(p2_RMSE)
dev.off()

save(p1_cor, p2_RMSE, file='_figures_COAD/COAD_box_plot_cor_RMSE.RData')


print(cormat)
print(err)
print(rss)

OneMinusCorr = 1-matrix(cormat,ncol = 1, byrow = FALSE)
RMSE     = matrix(err,ncol = 1, byrow = FALSE )
CellType = rep(cellTypes,length(methods))
Methods  = rep(methods,each = length(cellTypes))
res      = cbind.data.frame(OneMinusCorr, RMSE, CellType, Methods)

pdf('_figures_COAD/COAD_corr_vs_RMSE.pdf', width=5, height=4.5)
complot= ggplot(res, aes(x=OneMinusCorr,y=RMSE, color =  Methods)) + 
  ggtitle('COAD') + geom_point() + 
  scale_y_continuous(trans = log2_trans(),
                     breaks = trans_breaks('log10',function(x) 10^x),
                     labels = trans_format('log10',math_format(10^.x))) + 
  geom_text(label = res[,3])+xlim(0.1,1.05)
print(complot)
dev.off()

cormat_COAD = cormat
err_COAD    = err
save(cormat_COAD, file = '_figures_COAD/COAD_metrics_cor.RData')
save(err_COAD,    file = '_figures_COAD/COAD_metrics_RMSE.RData')

#---------------------------------------------------------------------
# a final summary plot
#---------------------------------------------------------------------

load('_figures_COAD/COAD_box_plot_cor_RMSE.RData')

load('_figures_COAD/COAD_plot_list_B.RData')
p31 = plist[[1]]+theme_cowplot()
p32 = plist[[2]]+theme_cowplot()

load('_figures_COAD/COAD_plot_list_NK.RData')
p41 = plist[[1]]+theme_cowplot()
p42 = plist[[2]]+theme_cowplot()

pdf('_figures_COAD/COAD_full.pdf',width=8, height = 10)
grid.arrange(grobs = list(p1_cor, p2_RMSE, p31, p32, p41, p42), ncol = 2)
dev.off()

sessionInfo()
gc()

quit(save = 'no')

