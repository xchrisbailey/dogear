// Keeps every Blob foliate turns into a URL, so ebook-to-epub.js can write the Blob into the EPUB
// in place of the URL. Imported first: fb2.js makes its stylesheet's URL as it loads.
export const blobs = new Map()

const createObjectURL = URL.createObjectURL.bind(URL)
URL.createObjectURL = object => {
    const url = createObjectURL(object)
    if (object instanceof Blob) blobs.set(url, object)
    return url
}
