import click
import re
import csv
import os


@click.command()
@click.argument("result_dir")
@click.argument("access_pattern")
@click.argument("args")
@click.argument("output_file")

def parse(result_dir, access_pattern, args, output_file):

    cwd = os.getcwd(); 
    os.chdir(cwd + "/" + result_dir)
    arg_arr = args.split(",")
    results = {}
    list_of_results = []
    list_of_fields = []

    for arg in arg_arr:
        results["Benchmark"] = arg
        for file in os.listdir():
            if (file.startswith(access_pattern) and file.startswith(arg, len(access_pattern) + 1)):

                result_file = file

                with open(result_file, "r") as f:
                    content = f.read()
                curr_results = re.findall(r"([\w\_]+)(?:\:\s+)([\d\.]+)", content)
            
                for result in curr_results:
                    counter_value = result[1]
                    counter_name = result[0]
                    results[counter_name] = counter_value
        list_of_results.append(results)
        results = {}

    for result in list_of_results:
        list_of_fields = list(set(list_of_fields + list(result.keys())))
    
    list_of_fields = sorted(list_of_fields, key=str.lower)

    with open(output_file, "w") as f:
        writer = csv.DictWriter(f, fieldnames=list_of_fields)
        writer.writeheader()
        for results in list_of_results:
            writer.writerow(results)


    # transposes the csv file
    # you can remove the following two lines to change the format of the file
    a = zip(*csv.reader(open(output_file, "r")))
    csv.writer(open(output_file, "w")).writerows(a)

if __name__ == "__main__":
    parse()