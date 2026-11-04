import unittest
from html.parser import HTMLParser
from pathlib import Path


class RecentLayoutParser(HTMLParser):
    def __init__(self):
        super().__init__()
        self.ids = []
        self.recent_note_present = False

    def handle_starttag(self, tag, attrs):
        identifier = dict(attrs).get('id')
        if identifier == 'bea-recent-jobs-note':
            self.recent_note_present = True
        if identifier in {'bea-recent-jobs-heading', 'bea-recent-pagination', 'bea-recent-jobs-list'}:
            self.ids.append(identifier)


class RecentPaginationLayoutTest(unittest.TestCase):
    def test_recent_history_has_no_redundant_retention_note(self):
        template = Path('BetterCallBliss/HTML/EN/plugins/BetterCallBliss/index.html')
        parser = RecentLayoutParser()
        parser.feed(template.read_text(encoding='utf-8'))
        self.assertFalse(parser.recent_note_present)

    def test_pagination_is_before_the_variable_height_recent_list(self):
        template = Path('BetterCallBliss/HTML/EN/plugins/BetterCallBliss/index.html')
        parser = RecentLayoutParser()
        parser.feed(template.read_text(encoding='utf-8'))
        self.assertEqual(parser.ids, [
            'bea-recent-jobs-heading', 'bea-recent-pagination', 'bea-recent-jobs-list',
        ])


if __name__ == '__main__':
    unittest.main()
