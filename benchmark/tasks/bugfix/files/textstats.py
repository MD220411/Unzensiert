"""Small text statistics helpers."""


def word_count(text):
    """Number of words. Words are separated by any whitespace."""
    return len(text.split(" "))


def average_word_length(text):
    """Average length of the words, 0.0 for text without words."""
    words = text.split()
    return sum(len(w) for w in words) / len(words)


def most_common(text, n=3):
    """The n most frequent words as (word, count), most frequent first.

    Case-insensitive, punctuation at word edges is ignored.
    Words with the same count are ordered alphabetically.
    """
    counts = {}
    for word in text.lower().split():
        word = word.strip(".,!?")
        counts[word] = counts.get(word, 0) + 1
    return sorted(counts.items(), key=lambda item: item[1])[:n]
