pandoc output.md -o output.pdf   --pdf-engine=xelatex -V sansfont="DejaVu Sans"   -V monofont="DejaVu Sans Mono" -V geometry:margin=.75in -V fontsize=12pt -V header-includes='\usepackage{fancyhdr} \pagestyle{fancy} \fancyhead[L]{Variant Output} \fancyhead[R]{\today}' --number-sections --highlight-style=kate

pandoc output.md -o output.html --standalone --css=https://sindresorhus.com/github-markdown-css/github-markdown.css --metadata title="Variant Output"
