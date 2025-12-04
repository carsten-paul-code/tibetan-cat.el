#!/usr/bin/env python3
"""
Extract compounds and proper nouns from tibetan-english.json dictionary.

This script:
1. Loads the comprehensive Tibetan-English dictionary
2. Filters for multi-syllable entries (containing spaces in Wylie)
3. Categorizes entries based on English definitions
4. Converts Wylie to Tibetan Unicode
5. Outputs to compounds.json and proper_nouns.json
"""

import json
import re
from pathlib import Path
from pyewts import pyewts

# Initialize Wylie converter
converter = pyewts()

def wylie_to_unicode(wylie_text):
    """Convert Wylie transliteration to Tibetan Unicode using pyewts."""
    if not wylie_text:
        return ""
    try:
        # pyewts expects space-separated syllables
        return converter.toUnicode(wylie_text)
    except Exception as e:
        print(f"  Warning: Could not convert '{wylie_text}': {e}")
        return None


class CategoryClassifier:
    """Classify dictionary entries into categories."""

    def __init__(self):
        # Person name indicators
        self.person_indicators = [
            r'\[p\.n\.\]', r'\[P\.N\.\]',
            r'ācārya', r'master', r'teacher', r'scholar',
            r'Nāgārjuna', r'Candrakīrti', r'Vasubandhu', r'Asaṅga',
            r'Āryadeva', r'Bhāvaviveka', r'Dharmakīrti',
        ]

        # Place name indicators
        self.place_indicators = [
            r'Śrāvastī', r'Rājagṛha', r'Vulture Peak', r'Jetavana',
            r'grove', r'park', r'city', r'mountain', r'monastery',
            r'India', r'Tibet', r'China', r'garden',
        ]

        # Buddha/Bodhisattva indicators
        self.buddha_indicators = [
            r'Buddha', r'Tathāgata', r'Amitā', r'Śākyamuni',
            r'Mañjuśrī', r'Avalokiteśvara', r'Samantabhadra',
            r'Maitreya', r'Vajrapāṇi', r'Kṣitigarbha',
        ]

        # Technical term indicators
        self.technical_indicators = [
            r'dharma', r'karma', r'saṃsāra', r'nirvāṇa',
            r'prajñā', r'śūnyatā', r'bodhicitta', r'karuṇā',
            r'aggregate', r'element', r'source',
            r'consciousness', r'wisdom', r'compassion',
            r'meditation', r'concentration', r'absorption',
            r'the\s+(five|six|seven|eight|ten|twelve)',  # numbered lists
        ]

        # Epithet indicators
        self.epithet_indicators = [
            r'Blessed One', r'Thus-Gone', r'Victor',
            r'Sage', r'Teacher', r'Supramundane Victor',
            r'Transcendent', r'One Gone Thus',
        ]

        # Connector/grammatical indicators
        self.connector_indicators = [
            r'^(moreover|therefore|thus|however|because|if|when|then|also|even|but|and)$',
            r'^(also|even|only|just|merely|alone)$',
        ]

        # Temporal phrase indicators
        self.temporal_indicators = [
            r'at that time', r'at this time', r'when', r'while',
            r'previously', r'formerly', r'in the past', r'in the future',
        ]

    def classify_entry(self, tibetan, english, notes, source):
        """Classify an entry and return (category_type, category, priority)."""
        english_lower = english.lower()

        # Check for Buddha/Bodhisattva (highest priority for proper nouns)
        if any(re.search(pattern, english, re.IGNORECASE) for pattern in self.buddha_indicators):
            return ('proper_noun', 'buddha_bodhisattva', 10)

        # Check for person names
        if any(re.search(pattern, english, re.IGNORECASE) for pattern in self.person_indicators):
            return ('proper_noun', 'person', 9)

        # Check for place names
        if any(re.search(pattern, english, re.IGNORECASE) for pattern in self.place_indicators):
            return ('proper_noun', 'place', 8)

        # Check for epithets (these are compounds, not proper nouns)
        if any(re.search(pattern, english, re.IGNORECASE) for pattern in self.epithet_indicators):
            return ('compound', 'epithet', 7)

        # Check for connectors (short grammatical words)
        if any(re.search(pattern, english_lower) for pattern in self.connector_indicators):
            return ('compound', 'connector', 6)

        # Check for temporal phrases
        if any(re.search(pattern, english_lower) for pattern in self.temporal_indicators):
            return ('compound', 'temporal_phrase', 5)

        # Check for technical terms
        if any(re.search(pattern, english_lower) for pattern in self.technical_indicators):
            return ('compound', 'technical_term', 4)

        # Default: general compound
        return ('compound', 'general', 1)


def extract_compounds_and_proper_nouns(input_file, output_dir):
    """Extract and categorize multi-syllable entries."""

    print(f"Loading dictionary from {input_file}")
    with open(input_file, 'r', encoding='utf-8') as f:
        data = json.load(f)

    print(f"Total entries: {len(data)}")

    # Filter for multi-syllable entries
    multi_syllable = [entry for entry in data if ' ' in entry['tibetan']]
    print(f"Multi-syllable entries: {len(multi_syllable)}")

    # Initialize classifier and storage
    classifier = CategoryClassifier()
    compounds_dict = {}
    proper_nouns_dict = {}

    # Statistics
    stats = {
        'compounds': {'epithet': 0, 'connector': 0, 'temporal_phrase': 0,
                     'technical_term': 0, 'general': 0},
        'proper_nouns': {'buddha_bodhisattva': 0, 'person': 0, 'place': 0}
    }

    print("\nCategorizing entries...")
    for entry in multi_syllable:
        tibetan_wylie = entry['tibetan']
        english = entry['english']
        notes = entry.get('notes', '')
        source = entry.get('source', 'Hopkins')

        # Convert Wylie to Unicode for dictionary key
        try:
            tibetan_unicode = wylie_to_unicode(tibetan_wylie)
        except Exception as e:
            print(f"Warning: Could not convert '{tibetan_wylie}': {e}")
            continue

        # Classify the entry
        category_type, category, priority = classifier.classify_entry(
            tibetan_wylie, english, notes, source
        )

        # Build entry data
        entry_data = {
            'wylie': tibetan_wylie,
            'english': english,
            'category': category,
            'source': source
        }

        # Extract Sanskrit if present
        sanskrit_match = re.search(r'([A-Z][a-zāīūṛṃḥṇśṣṭḍṅñ]+(?:[a-zāīūṛṃḥṇśṣṭḍṅñ]*)?)', english)
        if sanskrit_match:
            entry_data['sanskrit'] = sanskrit_match.group(1).lower()

        # Add to appropriate dictionary
        if category_type == 'proper_noun':
            proper_nouns_dict[tibetan_unicode] = entry_data
            stats['proper_nouns'][category] += 1
        else:  # compound
            compounds_dict[tibetan_unicode] = entry_data
            stats['compounds'][category] += 1

    # Save dictionaries
    output_dir = Path(output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    compounds_file = output_dir / 'compounds.json'
    proper_nouns_file = output_dir / 'proper_nouns.json'

    print(f"\nSaving {len(compounds_dict)} compounds to {compounds_file}")
    with open(compounds_file, 'w', encoding='utf-8') as f:
        json.dump(compounds_dict, f, ensure_ascii=False, indent=2)

    print(f"Saving {len(proper_nouns_dict)} proper nouns to {proper_nouns_file}")
    with open(proper_nouns_file, 'w', encoding='utf-8') as f:
        json.dump(proper_nouns_dict, f, ensure_ascii=False, indent=2)

    # Print statistics
    print("\n" + "="*60)
    print("EXTRACTION STATISTICS")
    print("="*60)
    print(f"\nCompounds ({len(compounds_dict)} total):")
    for cat, count in stats['compounds'].items():
        print(f"  {cat:20s}: {count:6d}")

    print(f"\nProper Nouns ({len(proper_nouns_dict)} total):")
    for cat, count in stats['proper_nouns'].items():
        print(f"  {cat:20s}: {count:6d}")

    # Sample entries
    print("\n" + "="*60)
    print("SAMPLE ENTRIES")
    print("="*60)

    print("\nSample Compounds:")
    for i, (tib, data) in enumerate(list(compounds_dict.items())[:10]):
        print(f"  {tib} = {data['english']} [{data['category']}]")

    print("\nSample Proper Nouns:")
    for i, (tib, data) in enumerate(list(proper_nouns_dict.items())[:10]):
        print(f"  {tib} = {data['english']} [{data['category']}]")

    print("\n" + "="*60)
    print("EXTRACTION COMPLETE")
    print("="*60)

    return compounds_dict, proper_nouns_dict


if __name__ == '__main__':
    # Paths
    base_dir = Path(__file__).parent.parent
    input_file = base_dir / 'data' / 'glossaries' / 'tibetan-english.json'
    output_dir = base_dir / 'data' / 'dictionaries'

    # Run extraction
    compounds, proper_nouns = extract_compounds_and_proper_nouns(input_file, output_dir)
