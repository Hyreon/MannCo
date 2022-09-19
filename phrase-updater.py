lines_start = []
lines_end = []

filename = "mannco-attributes.phrases.txt"
output_filename = "mannco-manager.phrases.txt"

with open(filename) as file:
    lines_start = file.readlines()

lines_end.append("Phrases")
lines_end.append("{")

for line in lines_start:
    if (line.startswith("\"")):
        line_components = line.split()
        lines_end.append("\t"+line_components[0])
        lines_end.append("\t{")
        lines_end.append("\t\t\"en\"\t" + (" ").join(line_components[1:]))
        lines_end.append("\t}")
    else:
        lines_end.append(line)

lines_end.append("}")

with open(output_filename, 'w') as file:
    for line in lines_end:
        file.write(line)
        file.write("\n")