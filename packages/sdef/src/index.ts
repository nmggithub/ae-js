import { writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { type Dictionary } from './elements.js';

function writeDictionaryToPathWithName(
    dictionary: Dictionary,
    path: string,
    name: string,
    options?: Parameters<Dictionary['getSdefXML']>[0],
) {
    const xml = dictionary.getSdefXML(options);
    const fullPath = join(path, `${name}.sdef`);
    writeFileSync(fullPath, xml);
}
export { writeDictionaryToPathWithName };
