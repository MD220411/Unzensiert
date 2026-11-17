from textstats import average_word_length, most_common, word_count


def test_word_count():
    assert word_count("one two three") == 3
    assert word_count("one  two\nthree\tfour") == 4
    assert word_count("") == 0


def test_average_word_length():
    assert average_word_length("ab abcd") == 3.0
    assert average_word_length("") == 0.0


def test_most_common():
    text = "The cat and the dog. The bird and the cat!"
    assert most_common(text, 2) == [("the", 4), ("and", 2)]
    assert most_common(text, 3) == [("the", 4), ("and", 2), ("cat", 2)]


if __name__ == "__main__":
    test_word_count()
    test_average_word_length()
    test_most_common()
    print("ALL TESTS PASSED")
