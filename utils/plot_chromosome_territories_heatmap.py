#!/usr/bin/env python3
# -*- coding:utf-8 -*-


import numpy as np
import os.path as op
import sys
import json

from collections import defaultdict
from math import log2



def create_trans_db(allpairs):
    prefix = allpairs.split("_")[0]
    db2 = defaultdict(lambda : 0)
    db = defaultdict(lambda : db2.copy())
    with open(allpairs) as fp:
        for line in fp:
            chrom1 = line.split()[1]
            chrom2 = line.split()[4]
            if chrom1 != chrom2:
                db[chrom1][chrom2] += 1
                db[chrom2][chrom1] += 1
    

    json.dump(db, open('{}_trans.json'.format(prefix), 'w'))


def cacl_total_trans(chrom_trans_nums):
    total_trans = 0
    for chrom in chrom_trans_nums:
        total_trans += sum(list(map(int, chrom_trans_nums[chrom].values())))
    return  total_trans


def get_chrom_list(chrom_list):
    if op.exists(chrom_list):
        chrom_list = [i.strip().split()[0] 
                for i in open(chrom_list) if i.strip()]
    else:
        chrom_list = chrom_list.strip(",").split(",")
    
    return chrom_list



def get_whole_obs_exp_matrix(allpairs, chrom_list):
    prefix = allpairs.split("_")[0]

    if not op.exists('{}_trans.json'.format(prefix)):
        create_trans_db(allpairs)
    else:
        print('[Warning]: There has already existed'
                ' `{}_trans.json`, using old json file.'.format(prefix))
    chrom_trans_nums = json.load(open('{}_trans.json'.format(prefix)))
    
    whole_obs_exp_matrix = np.zeros((len(chrom_list), len(chrom_list)))
    total_trans = cacl_total_trans(chrom_trans_nums)

    for i, chrom1 in enumerate(chrom_list):
        chrom1_trans = sum(list(map(int, chrom_trans_nums[chrom1].values())))
        for j, chrom2 in enumerate(chrom_list):
            if i==j :
                continue
            chrom2_trans = sum(list(map(int, chrom_trans_nums[chrom2].values())))
            obs = float(chrom_trans_nums[chrom1][chrom2])
            exp = (((chrom1_trans / total_trans) * (chrom2_trans / (total_trans - chrom1_trans)) + (chrom2_trans / total_trans) * (chrom1_trans / (total_trans - chrom2_trans))) * (total_trans / 2))
            whole_obs_exp_matrix[i][j] = log2(obs / exp)


    return whole_obs_exp_matrix


def plot_heatmap(whole_obs_exp_matrix, chrom_list, prefix,
        color='coolwarm', valfmt='{x: .3f}'):
    import matplotlib as mpl
    mpl.use('Agg')
    import matplotlib.pyplot as plt
    

    fig, ax = plt.subplots(figsize=(10, 10))
    im = ax.imshow(whole_obs_exp_matrix, cmap=color, vmax=0.13, vmin=-0.13)
    ax.figure.colorbar(im, ax=ax,fraction=0.045 )

    ax.set_xticks(np.arange(len(chrom_list)))
    ax.set_xticklabels(chrom_list)
    ax.set_yticks(np.arange(len(chrom_list)))
    ax.set_yticklabels(chrom_list)

    valfmt = mpl.ticker.StrMethodFormatter(valfmt)

    for i in range(len(chrom_list)):
        for j in range(len(chrom_list)):
            if i == j:
                continue
            text = ax.text(j, i, valfmt(whole_obs_exp_matrix[i, j], None),
                      ha='center', va='center')

    plt.savefig('{}_whole_chromosome_positions.pdf'.format(prefix), dpi=300)




if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("*"*79)
        print("Usage: {} sample.allValidPairs chrom.list".format(op.basename(sys.argv[0])))
        print("*"*79)
        sys.exit()
    allpairs, chrom_list = sys.argv[1:]
    chrom_list = get_chrom_list(chrom_list)
    matrix = get_whole_obs_exp_matrix(allpairs, chrom_list)
    prefix = allpairs.split("_")[0]
    plot_heatmap(matrix, chrom_list, prefix)