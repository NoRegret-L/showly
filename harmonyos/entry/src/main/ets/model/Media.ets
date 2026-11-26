export interface Media {
  id: string;
  title: string;
  kind: string;
  year: number;
  watched: boolean;
}

export interface Library {
  schema: number;
  items: Media[];
}

export function mediaLabel(item: Media): string {
  const year: string = item.year > 0 ? ' (' + item.year + ')' : '';
  const kind: string = item.kind === 'movie' ? '电影' : item.kind === 'show' ? '剧集' : '手动';
  return item.title + year + ' · ' + kind;
}

export function setWatched(items: Media[], id: string, watched: boolean): Media[] {
  return items.map((item: Media): Media => {
    if (item.id !== id) {
      return item;
    }
    return { id: item.id, title: item.title, kind: item.kind, year: item.year, watched: watched };
  });
}
