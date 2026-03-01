#!/usr/bin/env python3
import sys
import json
from pygooglenews import GoogleNews
from bs4 import BeautifulSoup

def search_artist_news(artist_name):
    """
    Searches for news about an artist using Google News and returns a list of articles.
    Uses quoted artist name + music keywords for better relevance.
    Searches both English and French sources.
    """
    try:
        articles = []
        seen_urls = set()

        # Search in English
        gn_en = GoogleNews(lang='en', country='US')
        search_query_en = f'"{artist_name}" music OR band OR album OR concert OR tour'
        search_en = gn_en.search(search_query_en, when='30d')

        for entry in search_en['entries'][:4]:
            if entry.link not in seen_urls:
                seen_urls.add(entry.link)
                soup = BeautifulSoup(entry.summary, 'html.parser')
                articles.append({
                    'title': entry.title,
                    'url': entry.link,
                    'source': entry.source['title'],
                    'date': entry.published,
                    'snippet': soup.get_text()
                })

        # Search in French
        gn_fr = GoogleNews(lang='fr', country='FR')
        search_query_fr = f'"{artist_name}" musique OR groupe OR album OR concert OR tournée'
        search_fr = gn_fr.search(search_query_fr, when='30d')

        for entry in search_fr['entries'][:4]:
            if entry.link not in seen_urls:
                seen_urls.add(entry.link)
                soup = BeautifulSoup(entry.summary, 'html.parser')
                articles.append({
                    'title': entry.title,
                    'url': entry.link,
                    'source': entry.source['title'],
                    'date': entry.published,
                    'snippet': soup.get_text()
                })

        # Sort by date and limit to 5
        articles.sort(key=lambda x: x['date'], reverse=True)
        articles = articles[:5]

        return {'articles': articles}

    except Exception as e:
        return {'error': str(e)}

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print(json.dumps({'error': 'No artist name provided.'}))
        sys.exit(1)

    artist_name_arg = sys.argv[1]
    news_data = search_artist_news(artist_name_arg)
    
    # Ensure the output is clean JSON
    print(json.dumps(news_data, ensure_ascii=False))
