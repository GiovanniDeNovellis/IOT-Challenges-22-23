

#ifndef RADIO_ROUTE_H
#define RADIO_ROUTE_H

typedef nx_struct radio_route_msg {
	nx_uint16_t type;
	nx_uint16_t sender;
	nx_uint16_t node_requested; //Will also be used for the destination in case of data message
	nx_uint16_t value; // Will also be used as cost in case of reply message
} radio_route_msg_t;

enum {
  AM_RADIO_COUNT_MSG = 10,
};

#endif
