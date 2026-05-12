import socket
import datetime


def get_hostname():

    print(socket.gethostname())
    return socket.gethostname()


def get_date_dd_mm_yyyy():
    print(datetime.datetime.now().strftime("%d-%m-%Y"))
    return datetime.datetime.now().strftime("%d-%m-%Y")


get_hostname()
get_date_dd_mm_yyyy()
