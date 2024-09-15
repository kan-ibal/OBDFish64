#include "bluetoothdata.h"
//#include <../qtconnectivity-5.2_sailfish_backport/src/bluetooth/qbluetoothsocket.h>

BluetoothData::BluetoothData (QObject *parent):QObject(parent)
{

}

BluetoothData::~BluetoothData ()
{
    if(this->_socket){
        delete this->_socket;
        this->_socket = 0;
        }
}

void BluetoothData::connect(QString address, int port)
{
    this->_port = port;
    this->_socket = new QBluetoothSocket(QBluetoothServiceInfo::RfcommProtocol);
    qDebug("Trying to connect to: %s_%d", address.toUtf8().constData(), _port);

//    if(this->_socket)
//        delete this->_socket;

    QObject::connect(this->_socket, SIGNAL(readyRead()), this, SLOT(readData()));
    QObject::connect(this->_socket, SIGNAL(connected()), this, SLOT(connected()));
    QObject::connect(this->_socket, SIGNAL(disconnected()), this, SLOT(disconnected()));
    QObject::connect(this->_socket, SIGNAL(error(QBluetoothSocket::SocketError error)), this, SLOT(error(QBluetoothSocket::SocketError error)));

    qDebug("Connecting...");
    this->_socket->connectToService(QBluetoothAddress(address), this->_port);
}

void BluetoothData::connected()
{
    qDebug() << "Connected";

    emit this->sigConnected();
}
void BluetoothData::disconnected()
{
    qDebug() << "Disconnected!";

    emit this->sigDisconnected();
}
void BluetoothData::error(QBluetoothSocket::SocketError errorCode)
{
    qDebug() << "Error: " << this->_socket->errorString();
    qDebug() << "Errorcode: " << errorCode;

    emit this->sigError(this->_socket->errorString());
}


void BluetoothData::disconnect()
{
    qDebug("Disconnecting...");

    if(!this->_socket)
        return;

    if(this->_socket->isOpen())
        this->_socket->close();

    delete this->_socket;

    qDebug("Disconnected.");
}

void BluetoothData::readData()
{
    qDebug("Entering readData...");

    QByteArray data = _socket->readAll();

    qDebug() << "Data size:" << data.size();
    qDebug() << "Data[" + QString::number(_port) + "]:" << data.toHex();

    qDebug() << "Text: " << data;

    emit this->sigReadDataReady(data);
}

void BluetoothData::sendHex(QString sString)
{
    //qDebug() << "sString: " << sString;

    QByteArray data = sString.toUtf8();

    //qDebug() << "data1: " << data.toHex();

    data.append("\r");

    //qDebug() << "data2: " << data.toHex();

    this->write(data);
}

qint64 BluetoothData::write(QByteArray data)
{
    qDebug() << "Writing:" << data.toHex();


    qint64 ret = this->_socket->write(data);


    //qint64 ret = this->_socket->write("ATZ\r");
    //ret = this->_socket->write("AT RV\r");
    //qint64 ret = this->_socket->write("AT L0\r");

    qDebug() << "Write returned:" << ret;



    return ret;
}
