#!/bin/bash

function perf_run() {
    obj_dir/Vmips_core -b "$1" > "$2"
}

benchmark_array=(
    "esift2"
    "nqueens"
    "qsort"
    "coin"
)

dir_name="benchmark_results"

make clean
make verilate

mkdir -p "$dir_name"

for file in "${benchmark_array[@]}"; do
    perf_run \
        "$file" \
        "benchmark_results/$1-${file}.txt"
done

python3 parse_all_bench.py ${dir_name} $1 "esift2,nqueens,qsort,coin" $1.csv

rm ${dir_name}/*.txt