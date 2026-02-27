import os
import re


def resolve_conflicts(directory):
    """resolve_conflicts function."""
    for root, dirs, files in os.walk(directory):
        if "venv" in root or "node_modules" in root or ".git" in root:
            continue
        for file in files:
            if file.endswith((".tf", ".py", ".md", ".sh", ".yaml", ".yml", ".json", ".txt")):
                filepath = os.path.join(root, file)
                try:
                    with open(filepath, encoding="utf-8") as f:
                        content = f.read()

                    if "<<<<<<< HEAD" in content:
                        print(f"Resolving conflicts in {filepath}")
                        # Pattern to match everything between <<<<<<< HEAD and =======
                        # and everything between ======= and >>>>>>> ...
                        # We keep the HEAD part.
                        pattern = re.compile(
                            r"<<<<<<< HEAD\n(.*?)\n?=======\n.*?\n?>>>>>>>.*?\n?",
                            re.DOTALL,
                        )
                        new_content = pattern.sub(r"\1", content)

                        with open(filepath, "w", encoding="utf-8") as f:
                            f.write(new_content)
                except Exception as e:
                    print(f"Error processing {filepath}: {e}")


if __name__ == "__main__":
    resolve_conflicts(".")
