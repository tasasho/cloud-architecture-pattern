/**
 * Triggered from a message on a Cloud Storage bucket.
 *
 * @param {!Object} event The Cloud Functions event.
 * @param {!Function} The callback function.
 */
exports.processFile = (event, callback) => {
    // Imports the Google Cloud client library
    const speech = require('@google-cloud/speech');
    const storage = require('@google-cloud/storage')();

    // Instantiates a client
    const client = new speech.SpeechClient();

    // Get Information about put object of Cloud Storage 
    const uploadedObject = event.data; // The Cloud Storage object.
    const gcsUri = 'gs://' + uploadedObject.bucket + '/' + uploadedObject.name; // Uploaded object's URI.
    const contentType = uploadedObject.contentType; // Object's content type.

    console.log('URI of processing file : ' + gcsUri);
    console.log('Type of processing file : ' + contentType);

    // Except for audio file, expire function.
    const arrForExtension = uploadedObject.name.split('.');
    if(arrForExtension[arrForExtension.length -1].toLowerCase() !== 'flac'){
      console.log('Uploaded file is not flac. This function does nothing.');
      return callback();
    }
  
    // Configure about GCE object which is saved translated text.
    const arrForFileName = arrForExtension[arrForExtension.length -2].split('/');
    const textBucketName = 'traslated-texts-137593963297';
    const textFilePath = 'texts/' + arrForFileName[arrForFileName.length -1] + '.txt';
    const textFile = storage.bucket(textBucketName).file(textFilePath);

    // The encoding of the audio file, e.g. 'LINEAR16'
    const encoding = 'FLAC';
    // The BCP-47 language code to use, e.g. 'en-US'
    const languageCode = 'ja-JP';
    // This param is optional for flac. The sample rate of the audio file in hertz, e.g. 16000.
    // const sampleRateHertz = 44100;

    const config = {
      encoding: encoding,
      languageCode: languageCode
    };

    const audio = {
      uri: gcsUri
    };

    const request = {
      config: config,
      audio: audio
    };

    // Detects speech in the audio file. This creates a recognition job that you
    // can wait for now, or get its result later.
    client.longRunningRecognize(request)
      .then((data) => {
        const operation = data[0];
        // Get a Promise representation of the final result of the job
        return operation.promise();
      })
      .then((data) => {
        const response = data[0];
        const transcription = response.results.map(result =>
            result.alternatives[0].transcript).join('\n');
        return textFile.save(transcription)
      })
      .then(() => {
        console.log('Translated text file is saved.');
        callback();
      })
      .catch((err) => {
        console.error('ERROR:', err);
        callback(err);
      });
};


