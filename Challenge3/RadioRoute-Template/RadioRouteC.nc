
/*
*	IMPORTANT:
*	The code will be avaluated based on:
*		Code design  
*
*/
 
 
#include "Timer.h"
#include "RadioRoute.h"
#define num_nodes 7


module RadioRouteC @safe() {
  uses {
  
    /****** INTERFACES *****/
	interface Boot;

    //interfaces for communication
    interface Receive;
    interface AMSend;
    interface SplitControl as AMControl;
    interface Packet;
    
	//interface for timers
	interface Timer<TMilli> as Timer0;
	interface Timer<TMilli> as Timer1;
	
	//interface for LED
	interface Leds;
	
    //other interfaces, if needed
  }
}
implementation {

  typedef struct {
  	uint16_t destination;
  	uint16_t next_hop;
  	uint16_t cost;
} RoutingEntry;
  
  RoutingEntry routing_table[num_nodes]; 
  
  message_t packet;
  message_t dataP;
  
  // Variables to store the message to send
  message_t queued_packet;
  uint16_t queue_addr;
  uint16_t time_delays[7]={61,173,267,371,479,583,689}; //Time delay in milli seconds
  int person_code[8] = {1, 0, 6, 0, 8, 6, 7, 2};
  int num_received=0; //Number of messages received 
  
  
  
  bool route_req_sent=FALSE;
  bool route_rep_sent=FALSE;
  
  bool sentData=FALSE;
  
  
  bool locked;
  
  bool actual_send (uint16_t address, message_t* packet);
  bool generate_send (uint16_t address, message_t* packet, uint8_t type);
  
  
  
  
  bool generate_send (uint16_t address, message_t* packet, uint8_t type){
  /*
  * 
  * Function to be used when performing the send after the receive message event.
  * It store the packet and address into a global variable and start the timer execution to schedule the send.
  * It allow the sending of only one message for each REQ and REP type
  * @Input:
  *		address: packet destination address
  *		packet: full packet to be sent (Not only Payload)
  *		type: payload message type
  *
  * MANDATORY: DO NOT MODIFY THIS FUNCTION
  */
  	if (call Timer0.isRunning()){
  		return FALSE;
  	}else{
  	if (type == 1 && !route_req_sent ){
  		route_req_sent = TRUE;
  		call Timer0.startOneShot( time_delays[TOS_NODE_ID-1] );
  		queued_packet = *packet;
  		queue_addr = address;
  	}else if (type == 2 && !route_rep_sent){
  	  	route_rep_sent = TRUE;
  		call Timer0.startOneShot( time_delays[TOS_NODE_ID-1] );
  		queued_packet = *packet;
  		queue_addr = address;
  	}else if (type == 0){
  		call Timer0.startOneShot( time_delays[TOS_NODE_ID-1] );
  		queued_packet = *packet;
  		queue_addr = address;	
  	}
  	}
  	return TRUE;
  }
  
  event void Timer0.fired() {
  	/*
  	* Timer triggered to perform the send.
  	* MANDATORY: DO NOT MODIFY THIS FUNCTION
  	*/
  	dbg("radio", "Timer 0 fired \n");
  	actual_send (queue_addr, &queued_packet);
  }
  
  bool actual_send (uint16_t address, message_t* packet){
	/*
	* Implement here the logic to perform the actual send of the packet using the tinyOS interfaces
	*/
	if(locked){
		dbg("radio", "Locked \n");
		return;
		}
	if (call AMSend.send(address, packet, sizeof(radio_route_msg_t)) == SUCCESS) {
		dbg("radio_send", "Sending packet");	
		locked = TRUE;
		dbg_clear("radio_send", " at time %s \n", sim_time_string());
      }
	  
  }
  
  //Just printing the node id for debug and calling the AMControl start
  event void Boot.booted() {
    dbg("boot","Application booted for node: %d \n", TOS_NODE_ID);
    call AMControl.start();
  }
	
  //In case of success, I print the node id for debug and then check 
  //if I am the first node and need to send the data message after 5 seconds.
  //In case of error I just print a debug message signaling it and retry to start.
  event void AMControl.startDone(error_t err) {
	if (err == SUCCESS) {
      dbg("radio","Radio on on node %d!\n", TOS_NODE_ID);
      if(TOS_NODE_ID==1)
      	call Timer1.startOneShot(5000);
    }
    else {
      dbgerror("radio", "Radio failed to start for node %d, retrying...\n", TOS_NODE_ID);
      call AMControl.start();
    }
  }
  
  //Printing a debug message in case of stop
  event void AMControl.stopDone(error_t err) {
    dbg("boot","Application stopped for node: %d \n", TOS_NODE_ID);
  }
  
  event void Timer1.fired() {
	/*
	* Implement here the logic to trigger the Node 1 to send the first REQ packet
	*/
	int destAddress=7;
	radio_route_msg_t* contentToSend = (radio_route_msg_t*)call Packet.getPayload(&dataP, sizeof(radio_route_msg_t));
	radio_route_msg_t* broadReq = (radio_route_msg_t*)call Packet.getPayload(&packet, sizeof(radio_route_msg_t));
	dbg("radio", "Timer 1 fired \n");
	if(routing_table[destAddress-1].destination==NULL){
		//Destination not present in the routing table, need to ask for a path
		broadReq->type = 1;
		broadReq->node_requested=7;
		generate_send(AM_BROADCAST_ADDR, &packet, 1);
	}
	else{
		//Destination present, can send the data message
		contentToSend->type = 0;
		contentToSend->sender = 1;
		contentToSend->node_requested=7;
		contentToSend->value=5;
		dbg("radio", "Can send the data, next hop: %d \n", routing_table[destAddress-1].next_hop);
		generate_send(routing_table[destAddress-1].next_hop, &dataP, 0);
	}
}

  //Function called when any type of message is received, it updates the counter and toggle the correct led based 
  //on the person code digit.
  void handleLeds(){
  	int person_digit = person_code[num_received%8];
  	int led_index=person_digit%3;
  	num_received++;
    if(led_index==0)
    	call Leds.led0Toggle();
    else if(led_index==1)
    	call Leds.led1Toggle();
    else
    	call Leds.led2Toggle();
    dbg("radio", "Node %d received %d messages, current code digit: %d , updated led %d \n", TOS_NODE_ID, num_received, person_digit, led_index);  
    // 0 means off, >0 means on
    dbg("led_0", "Led 0 status %u\n", call Leds.get() & LEDS_LED0);
    dbg("led_1", "Led 1 status %u\n", call Leds.get() & LEDS_LED1);
    dbg("led_2", "Led 2 status %u\n", call Leds.get() & LEDS_LED2);
  }
	

  event message_t* Receive.receive(message_t* bufPtr, 
				   void* payload, uint8_t len) {
	/*
	* Parse the receive packet.
	* Implement all the functionalities
	* Perform the packet send using the generate_send function if needed
	* Implement the LED logic and print LED status on Debug
	*/
	if (len != sizeof(radio_route_msg_t)) {return bufPtr;}
	else{
		radio_route_msg_t* rcm = (radio_route_msg_t*)payload;
		handleLeds();
		if(rcm->type==0){ //Received a data message
			int node_requested = rcm->node_requested;
			dbg("radio","Node %d received a data message\n", TOS_NODE_ID);
			if(node_requested==TOS_NODE_ID){
			//I am the destination of the data, do nothing
			dbg("radio","Node %d was the destination of data %d from node %d \n", TOS_NODE_ID, rcm->value, rcm->sender);
			}
			else{
			//Check routing table for next hop
			//I am assuming that if i received a data message, it means I am in the routing table of the sender node as next_hop, 
			// so I sent previously a route reply and i have the destination node in my table.
			int next_hop = routing_table[node_requested-1].next_hop;
			radio_route_msg_t* contentToSend = (radio_route_msg_t*)call Packet.getPayload(&packet, sizeof(radio_route_msg_t));
			contentToSend->type=0;
			contentToSend->sender=rcm->sender;
			contentToSend->node_requested=rcm->node_requested;
			contentToSend->value=rcm->value;
			generate_send(next_hop, &packet, 0);
			}
		}
		else if(rcm->type==1){ //Received a route request message
			int node_requested = rcm->node_requested;
			dbg("radio","Node %d received a route request message for %d \n", TOS_NODE_ID, node_requested);
			if(node_requested==TOS_NODE_ID){
				//I am the requested node
				radio_route_msg_t* contentToSend = (radio_route_msg_t*)call Packet.getPayload(&packet, sizeof(radio_route_msg_t));
				contentToSend->type=2;
				contentToSend->sender=TOS_NODE_ID;
				contentToSend->node_requested=TOS_NODE_ID;
				contentToSend->value=1;
				generate_send(AM_BROADCAST_ADDR, &packet, 2);
			}
			else{
				if(routing_table[node_requested-1].destination==NULL){
					//The node requested is not in my routing table
					radio_route_msg_t* contentToSend = (radio_route_msg_t*)call Packet.getPayload(&packet, sizeof(radio_route_msg_t));
					contentToSend->type=1;
					contentToSend->node_requested=node_requested;
					generate_send(AM_BROADCAST_ADDR, &packet, 1);
				}
				else{
					//The node requested is in my routing table
					radio_route_msg_t* contentToSend = (radio_route_msg_t*)call Packet.getPayload(&packet, sizeof(radio_route_msg_t));
					contentToSend->type=2;
					contentToSend->sender=TOS_NODE_ID;
					contentToSend->node_requested=node_requested;
					contentToSend->value=routing_table[node_requested-1].cost+1;
					generate_send(AM_BROADCAST_ADDR, &packet, 2);
				}
			}
		}
		else{ //Received a route reply message
			int node_requested = rcm->node_requested;
			dbg("radio","Node %d received a route reply message\n", TOS_NODE_ID);
			if(node_requested==TOS_NODE_ID){
			 //I am the node requested in the reply, do nothing
			 dbg("radio", "I am the request of the reply, do nothing \n");
			}
			else{
				if(routing_table[node_requested-1].destination==NULL || routing_table[node_requested-1].cost>rcm->value){
				//The node requested is not in my routing table or the new cost is lower than the previous one, update the routing table
					radio_route_msg_t* contentToSend = (radio_route_msg_t*)call Packet.getPayload(&packet, sizeof(radio_route_msg_t));
					routing_table[node_requested-1].destination=node_requested;
					routing_table[node_requested-1].cost=rcm->value;
					routing_table[node_requested-1].next_hop=rcm->sender;
					contentToSend->type=2;
					contentToSend->sender=TOS_NODE_ID;
					contentToSend->node_requested=node_requested;
					contentToSend->value=routing_table[node_requested-1].cost+1;
					dbg("radio", "Updating routing and sending cost for node %d \n", node_requested);
					if(TOS_NODE_ID==1 && node_requested==7 && sentData==FALSE){
						//Node 1 received the path for the node 7, can send the data
						sentData=TRUE;
						call Timer1.startOneShot(1000);
					}
					generate_send(AM_BROADCAST_ADDR, &packet, 2);
				}
				else{
					//The node requested is in my routing table, but the new cost is higher than the previous one, do nothing.
					dbg("radio", "Node already present or cost higher than previous, do nothing \n");
				}
			}
		}
	}
	return bufPtr;
  }

  event void AMSend.sendDone(message_t* bufPtr, error_t error) {
	/* This event is triggered when a message is sent 
	*  Check if the packet is sent 
	*/ 
	if (&queued_packet == bufPtr) {
      locked = FALSE;
      dbg("radio_send", "Packet sent...");
      dbg_clear("radio_send", " at time %s \n", sim_time_string());
    }
    else{
    	dbg("radio", "send ack error \n");
    }
  }
}




