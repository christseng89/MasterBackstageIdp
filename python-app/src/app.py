from flask import Flask, jsonify
import datetime
import socket


app = Flask(__name__)


@app.route('/api/v1/info')
def info():
    return jsonify({
        'time': datetime.datetime.now().strftime("%I:%M:%S%p  on %B %d, %Y"),
        'hostname': socket.gethostname(),
        'message': 'You are doing great, human! <3 Changed in v3 via ARC v3',
        'deployed_on': 'kubernetes'
    })


@app.route('/api/v1/healthz')
def health():
    # Do an actual check here
    return jsonify({'status': 'up'}), 200


@app.route('/')
def root():
    return 'Hello World!'


if __name__ == '__main__':

    app.run(host="0.0.0.0")
