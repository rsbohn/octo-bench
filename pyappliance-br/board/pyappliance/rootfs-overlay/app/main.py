# read input line
# remove all spaces
# sort by characters

def main():
    print("Welcome to Troll HQ.")
    while True:
        line = input("? ")
        line = line.replace(" ", "")
        line = "".join(sorted(line))
        # Remove duplicate characters after sorting
        line = "".join(dict.fromkeys(line))
        print(line)
        if line == "iqtu":
            break

if __name__ == "__main__":
    try:
        main()
    except EOFError:
        pass
    print("\nFare thee well!")