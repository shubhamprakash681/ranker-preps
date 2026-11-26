import cf from 'cloudfront';

const kvsHandle = cf.kvs();

async function handler(event) {
  let awsWeight = 100;
  try {
    const val = await kvsHandle.get('aws_weight');
    const parsed = parseInt(val, 10);
    if (!isNaN(parsed)) {
      awsWeight = Math.max(0, Math.min(100, parsed));
    }
  } catch (e) {
    awsWeight = 100;
  }

  if (awsWeight === 0 || (awsWeight < 100 && Math.random() * 100 >= awsWeight)) {
    cf.selectRequestOriginById('gcp-origin');
  }

  return event.request;
}
