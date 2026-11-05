import { MongoClient } from 'mongodb';

const uri = process.env.MONGODB_URI ?? '';
if (!uri.startsWith('mongodb+srv://') || !uri.includes('.mongodb.net')) {
  console.error(JSON.stringify({ ok: false, error: 'Set a MongoDB Atlas URI in MONGODB_URI. Credentials are never printed.' }));
  process.exitCode = 1;
} else {
  const client = new MongoClient(uri, { serverSelectionTimeoutMS: 10000 });
  try {
    await client.connect();
    await client.db(process.env.MONGODB_DB || 'nfinit_coop').command({ ping: 1 });
    console.log(JSON.stringify({ ok: true, storage: 'MongoDB Atlas cloud', testRecordsWritten: false }));
  } catch (error) {
    console.error(JSON.stringify({ ok: false, error: error.name, code: error.code ?? null }));
    process.exitCode = 1;
  } finally { await client.close(); }
}
