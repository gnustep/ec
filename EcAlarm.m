
/** Enterprise Control Configuration and Logging

   Copyright (C) 2012 Free Software Foundation, Inc.

   Written by: Richard Frith-Macdonald <rfm@gnu.org>
   Date: Febrary 2010
   Originally developed from 1996 to 2012 by Brainstorm, and donated to
   the FSF.

   This file is part of the GNUstep project.

   This library is free software; you can redistribute it and/or
   modify it under the terms of the GNU Lesser General Public
   License as published by the Free Software Foundation; either
   version 3 of the License, or (at your option) any later version.

   This library is distributed in the hope that it will be useful,
   but WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
   Library General Public License for more details.

   You should have received a copy of the GNU Lesser General Public
   License along with this library; if not, write to the Free
   Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
   Boston, MA 02111 USA.

   */

#import <Foundation/NSArray.h>
#import <Foundation/NSCoder.h>
#import <Foundation/NSDate.h>
#import <Foundation/NSException.h>
#import <Foundation/NSHost.h>
#import <Foundation/NSObject.h>
#import <Foundation/NSString.h>

#import "EcProcess.h"
#import "EcAlarm.h"

@class	NSPortCoder;

NSString *
EcMakeManagedObject(NSString *host, NSString *process, NSString *component)
{
  NSString	*instance = @"";
  NSRange	r;

  if (nil == host)
    {
      host = [[NSHost currentHost] name];
    }
  else
    {
      // No underscores permitted.
      host = [host stringByReplacingString: @"_" withString: @"-"];
    }

  if (nil == process)
    {
      process = [EcProc cmdName];
    }

  /* Extract the instance number from the process name (the instance would
   * be a string of digits after a hyphen) if it's there.
   */
  r = [process rangeOfString: @"-"
		     options: NSCaseInsensitiveSearch|NSBackwardsSearch];
  if (r.length > 0)
    {
      NSString	*s = [process substringFromIndex: NSMaxRange(r)];
      unsigned	l = [s length];

      if (l > 0)
	{
	  while (l-- > 0)
	    {
	      unichar	c = [s characterAtIndex: l];

	      if (c < '0' || c > '9')
		{
		  break;
		}
	    }
	  if (0 == l)
	    {
	      instance = s;
	      process = [process substringToIndex: r.location];
	    }
	}
    }
  // No underscores permitted.
  process = [process stringByReplacingString: @"_" withString: @"-"];

  if (nil == component)
    {
      component = @"";
    }
  else
    {
      // No underscores permitted.
      component = [component stringByReplacingString: @"_" withString: @"-"];
    }

  return [NSString stringWithFormat: @"%@_%@_%@_%@", 
    host, process, instance, component];
}



@implementation	EcAlarm

+ (EcAlarm*) alarmForManagedObject: (NSString*)managedObject
				at: (NSDate*)eventDate
		     withEventType: (EcAlarmEventType)eventType
		     probableCause: (EcAlarmProbableCause)probableCause
		   specificProblem: (NSString*)specificProblem
		 perceivedSeverity: (EcAlarmSeverity)perceivedSeverity
	      proposedRepairAction: (NSString*)proposedRepairAction
		    additionalText: (NSString*)additionalText
{
  EcAlarm	*a = [self alloc];

  a = [a initForManagedObject: managedObject
			   at: eventDate
		withEventType: eventType
		probableCause: probableCause
	      specificProblem: specificProblem
	    perceivedSeverity: perceivedSeverity
	 proposedRepairAction: proposedRepairAction
	       additionalText: additionalText];
  return [a autorelease];
}

+ (EcAlarmEventType) eventTypeFromProbableCause: (EcAlarmProbableCause)value
{
  switch (value)
    {
      case EcAlarmProbableCauseUnknown:	// Don't call with this value
	return EcAlarmEventTypeUnknown;

      case EcAlarmCallEstablishmentError:
      case EcAlarmCommunicationsProtocolError:
      case EcAlarmCommunicationsSubsystemFailure:
      case EcAlarmDegradedSignal:
      case EcAlarmDTE_DCEInterfaceError:
      case EcAlarmFramingError:
      case EcAlarmLANError:
      case EcAlarmLocalNodeTransmissionError:
      case EcAlarmLossOfFrame:
      case EcAlarmLossOfSignal:
      case EcAlarmRemoteNodeTransmissionError:
	return EcAlarmEventTypeCommunications;

      case EcAlarmEnclosureDoorOpen:
      case EcAlarmExcessiveVibration:
      case EcAlarmFireDetected:
      case EcAlarmFloodDetected:
      case EcAlarmHeatingOrVentilationOrCoolingSystemProblem:
      case EcAlarmHumidityUnacceptable:
      case EcAlarmLeakDetected:
      case EcAlarmMaterialSupplyExhausted:
      case EcAlarmPressureUnacceptable:
      case EcAlarmPumpFailure:
      case EcAlarmTemperatureUnacceptable:
      case EcAlarmToxicLeakDetected:
	return EcAlarmEventTypeEnvironmental;

      case EcAlarmAdapterError:
      case EcAlarmDataSetOrModemError:
      case EcAlarmEquipmentMalfunction:
      case EcAlarmInputDeviceError:
      case EcAlarmInputOutputDeviceError:
      case EcAlarmMultiplexerProblem:
      case EcAlarmOuputDeviceError:
      case EcAlarmPowerProblem:
      case EcAlarmProcessorProblem:
      case EcAlarmReceiveFailure:
      case EcAlarmReceiverFailure:
      case EcAlarmTimingProblem:
      case EcAlarmTransmitFailure:
      case EcAlarmTransmitterFailure:
	return EcAlarmEventTypeEquipment;

      case EcAlarmApplicationSubsystemFailure:
      case EcAlarmConfigurationOrCustomizationError:
      case EcAlarmCorruptData:
      case EcAlarmCpuCyclesLimitExceeded:
      case EcAlarmFileError:
      case EcAlarmOutOfMemory:
      case EcAlarmSoftwareProgramAbnormallyTerminated:
      case EcAlarmSoftwareProgramError:
      case EcAlarmStorageCapacityProblem:
      case EcAlarmUnderlyingResourceUnavailable:
      case EcAlarmVersionMismatch:
	return EcAlarmEventTypeProcessingError;

      case EcAlarmBandwidthReduced:
      case EcAlarmCongestion:
      case EcAlarmPerformanceDegraded:
      case EcAlarmQueueSizeExceeded:
      case EcAlarmResourceAtOrNearingCapacity:
      case EcAlarmResponseTimeExcessive:
      case EcAlarmRetransmissionRateExcessive:
      case EcAlarmThresholdCrossed:
	return EcAlarmEventTypeQualityOfService;
    }
  return EcAlarmEventTypeUnknown;
}

+ (NSString*) stringFromEventType: (EcAlarmEventType)value
{
  switch (value)
    {
      case EcAlarmEventTypeUnknown:	// Not legal
	return nil;
      case EcAlarmEventTypeCommunications:
	return @"EcAlarmEventTypeCommunications";
      case EcAlarmEventTypeEnvironmental:
	return @"EcAlarmEventTypeEnvironmental";
      case EcAlarmEventTypeEquipment:
	return @"EcAlarmEventTypeEquipment";
      case EcAlarmEventTypeProcessingError:
	return @"EcAlarmEventTypeProcessingError";
      case EcAlarmEventTypeQualityOfService:
	return @"EcAlarmEventTypeQualityOfService";
    }
  return nil;
}

+ (NSString*) stringFromProbableCause: (EcAlarmProbableCause)value
{
  switch (value)
    {
      case EcAlarmProbableCauseUnknown:
	return @"EcAlarmProbableCauseUnknown";
      case EcAlarmAdapterError:
	return @"adapterError";
      case EcAlarmApplicationSubsystemFailure:
	return @"applicationSubsystemFailure";
      case EcAlarmBandwidthReduced:
	return @"bandwidthReduced";
      case EcAlarmCallEstablishmentError:
	return @"callEstablishmentError";
      case EcAlarmCommunicationsProtocolError:
	return @"communicationsProtocolError";
      case EcAlarmCommunicationsSubsystemFailure:
	return @"communicationsSubsystemFailure";
      case EcAlarmConfigurationOrCustomizationError:
	return @"configurationOrCustomizationError";
      case EcAlarmCongestion:
	return @"congestion";
      case EcAlarmCorruptData:
	return @"corruptData";
      case EcAlarmCpuCyclesLimitExceeded:
	return @"cpuCyclesLimitExceeded";
      case EcAlarmDataSetOrModemError:
	return @"dataSetOrModemError";
      case EcAlarmDegradedSignal:
	return @"degradedSignal";
      case EcAlarmDTE_DCEInterfaceError:
	return @"dTE-DCEInterfaceError";
      case EcAlarmEnclosureDoorOpen:
	return @"enclosureDoorOpen";
      case EcAlarmEquipmentMalfunction:
	return @"equipmentMalfunction";
      case EcAlarmExcessiveVibration:
	return @"excessiveVibration";
      case EcAlarmFileError:
	return @"fileError";
      case EcAlarmFireDetected:
	return @"fireDetected";
      case EcAlarmFloodDetected:
	return @"floodDetected";
      case EcAlarmFramingError:
	return @"framingError";
      case EcAlarmHeatingOrVentilationOrCoolingSystemProblem:
	return @"heatingOrVentilationOrCoolingSystemProblem";
      case EcAlarmHumidityUnacceptable:
	return @"humidityUnacceptable";
      case EcAlarmInputOutputDeviceError:
	return @"inputOutputDeviceError";
      case EcAlarmInputDeviceError:
	return @"inputDeviceError";
      case EcAlarmLANError:
	return @"lANError";
      case EcAlarmLeakDetected:
	return @"leakDetected";
      case EcAlarmLocalNodeTransmissionError:
	return @"localNodeTransmissionError";
      case EcAlarmLossOfFrame:
	return @"lossOfFrame";
      case EcAlarmLossOfSignal:
	return @"lossOfSignal";
      case EcAlarmMaterialSupplyExhausted:
	return @"materialSupplyExhausted";
      case EcAlarmMultiplexerProblem:
	return @"multiplexerProblem";
      case EcAlarmOutOfMemory:
	return @"outOfMemory";
      case EcAlarmOuputDeviceError:
	return @"ouputDeviceError";
      case EcAlarmPerformanceDegraded:
	return @"performanceDegraded";
      case EcAlarmPowerProblem:
	return @"powerProblem";
      case EcAlarmPressureUnacceptable:
	return @"pressureUnacceptable";
      case EcAlarmProcessorProblem:
	return @"processorProblem";
      case EcAlarmPumpFailure:
	return @"pumpFailure";
      case EcAlarmQueueSizeExceeded:
	return @"queueSizeExceeded";
      case EcAlarmReceiveFailure:
	return @"receiveFailure";
      case EcAlarmReceiverFailure:
	return @"receiverFailure";
      case EcAlarmRemoteNodeTransmissionError:
	return @"remoteNodeTransmissionError";
      case EcAlarmResourceAtOrNearingCapacity:
	return @"resourceAtOrNearingCapacity";
      case EcAlarmResponseTimeExcessive:
	return @"responseTimeExcessive";
      case EcAlarmRetransmissionRateExcessive:
	return @"retransmissionRateExcessive";
      case EcAlarmSoftwareProgramAbnormallyTerminated:
	return @"softwareProgramAbnormallyTerminated";
      case EcAlarmSoftwareProgramError:
	return @"softwareProgramError";
      case EcAlarmStorageCapacityProblem:
	return @"storageCapacityProblem";
      case EcAlarmTemperatureUnacceptable:
	return @"temperatureUnacceptable";
      case EcAlarmThresholdCrossed:
	return @"thresholdCrossed";
      case EcAlarmTimingProblem:
	return @"timingProblem";
      case EcAlarmToxicLeakDetected:
	return @"toxicLeakDetected";
      case EcAlarmTransmitFailure:
	return @"transmitFailure";
      case EcAlarmTransmitterFailure:
	return @"transmitterFailure";
      case EcAlarmUnderlyingResourceUnavailable:
	return @"underlyingResourceUnavailable";
      case EcAlarmVersionMismatch:
	return @"versionMismatch";
    }
  return nil;
}

+ (NSString*) stringFromSeverity: (EcAlarmSeverity)value
{
  switch (value)
    {
      case EcAlarmSeverityIndeterminate: return @"EcAlarmSeverityIndeterminate";
      case EcAlarmSeverityCritical: return @"EcAlarmSeverityCritical";
      case EcAlarmSeverityMajor: return @"EcAlarmSeverityMajor";
      case EcAlarmSeverityMinor: return @"EcAlarmSeverityMinor";
      case EcAlarmSeverityWarning: return @"EcAlarmSeverityWarning";
      case EcAlarmSeverityCleared: return @"EcAlarmSeverityCleared";
    }
  return nil;
}

+ (NSString*) stringFromTrend: (EcAlarmTrend)value
{
  switch (value)
    {
      case EcAlarmTrendNone: return @"EcAlarmTrendNone";
      case EcAlarmTrendUp: return @"EcAlarmTrendUp";
      case EcAlarmTrendDown: return @"EcAlarmTrendDown";
    }
  return nil;
}

- (NSString*) additionalText
{
  return _additionalText;
}

- (Class) classForCoder
{
  return [EcAlarm class];
}

- (EcAlarm*) clear
{
  EcAlarm	*c = [self copy];

  c->_perceivedSeverity = EcAlarmSeverityCleared;
  c->_notificationID = _notificationID;
  return [c autorelease];
}

- (NSComparisonResult) compare: (EcAlarm*)other
{
  int		oNotificationID;
  NSString	*sStr;
  NSString	*oStr;

  if (NO == [other isKindOfClass: [EcAlarm class]])
    {
      [NSException raise: NSInvalidArgumentException
		  format: @"[%@-%@] argument is not an EcAlarm",
	NSStringFromClass([self class]), NSStringFromSelector(_cmd)];
    }
  oNotificationID = [other notificationID];
  if (_notificationID > 0 && oNotificationID > 0)
    {
      if (_notificationID < oNotificationID)
	{
	  return NSOrderedAscending;
	}
      if (_notificationID > oNotificationID)
	{
	  return NSOrderedDescending;
	}
      return NSOrderedSame;
    }
  sStr = [NSString stringWithFormat: @"%@ %d %d %@",
    [self managedObject],
    [self eventType],
    [self probableCause],
    [self specificProblem]];
  oStr = [NSString stringWithFormat: @"%@ %d %d %@",
    [other managedObject],
    [other eventType],
    [other probableCause],
    [other specificProblem]];
  return [sStr compare: oStr];
}

- (id) copyWithZone: (NSZone*)aZone
{
  EcAlarm	*c = [[self class] allocWithZone: aZone];

  c = [c initForManagedObject: _managedObject
			   at: _eventDate
		withEventType: _eventType
		probableCause: _probableCause
	      specificProblem: _specificProblem
	    perceivedSeverity: _perceivedSeverity
	 proposedRepairAction: _proposedRepairAction
	       additionalText: _additionalText];
  if (nil != c)
    {
      c->_firstEventDate = [_firstEventDate copyWithZone: aZone];
      c->_notificationID = _notificationID;
      c->_trendIndicator = _trendIndicator;
    }
  return c;
}

- (void) dealloc
{
  DESTROY(_managedObject);
  DESTROY(_eventDate);
  DESTROY(_firstEventDate);
  DESTROY(_specificProblem);
  DESTROY(_proposedRepairAction);
  DESTROY(_additionalText);
  [super dealloc];
}

- (NSString*) description
{
  Class	c = [self class];

  return [NSString stringWithFormat:
    @"Alarm %-8d %@ %@ %@ %@ %@ at %@(%@) %@ %@ %@",
    _notificationID,
    _managedObject,
    [c stringFromEventType: _eventType],
    [c stringFromProbableCause: _probableCause],
    [c stringFromSeverity: _perceivedSeverity],
    [c stringFromTrend: _trendIndicator],
    _eventDate,
    _firstEventDate,
    _specificProblem,
    _proposedRepairAction,
    _additionalText];
}

- (void) encodeWithCoder: (NSCoder*)aCoder
{
  [aCoder encodeValuesOfObjCTypes: "iiiii@@@@@@",
    &_eventType,
    &_notificationID,
    &_perceivedSeverity,
    &_probableCause,
    &_trendIndicator,
    &_managedObject,
    &_eventDate,
    &_firstEventDate,
    &_specificProblem,
    &_proposedRepairAction,
    &_additionalText];
}

- (NSDate*) eventDate
{
  return _eventDate;
}

- (EcAlarmEventType) eventType
{
  return _eventType;
}

- (void *) extra
{
  return _extra;
}

- (NSDate*) firstEventDate
{
  return _firstEventDate;
}

- (void) freeze
{
  /* NB this value must NOT be archived ... because when we restore from
   * archive we will want to store a pointer in _extra.
   */
  _frozen = YES;
}

- (NSUInteger) hash
{
  return [_managedObject hash];
}

- (id) init
{
  [self release];
  [NSException raise: NSInvalidArgumentException
	      format: @"Called -init on EcAlarm"];
  return nil;
}

- (id) initForManagedObject: (NSString*)managedObject
			 at: (NSDate*)eventDate
	      withEventType: (EcAlarmEventType)eventType
	      probableCause: (EcAlarmProbableCause)probableCause
	    specificProblem: (NSString*)specificProblem
	  perceivedSeverity: (EcAlarmSeverity)perceivedSeverity
       proposedRepairAction: (NSString*)proposedRepairAction
	     additionalText: (NSString*)additionalText
{
  Class	c = [self class];

  if (nil == managedObject)
    {
      managedObject = EcMakeManagedObject(nil, nil, nil);
    }
  if (4 != [[managedObject componentsSeparatedByString: @"_"] count])
    {
      [self release];
      [NSException raise: NSInvalidArgumentException
		  format: @"bad managed object (%@)", managedObject];
    }
  if (127 < strlen([managedObject UTF8String]))
    {
      [self release];
      [NSException raise: NSInvalidArgumentException
	format: @"managed object too long (over 127 bytes): (%@)",
	managedObject];
    }
  if (0 == [specificProblem length])
    {
      [self release];
      [NSException raise: NSInvalidArgumentException
		  format: @"empty specific problem"];
    }
  if (255 < strlen([specificProblem UTF8String]))
    {
      [self release];
      [NSException raise: NSInvalidArgumentException
	format: @"specific problem too long (over 255 bytes): (%@)",
	specificProblem];
    }
  if (0 == [proposedRepairAction length])
    {
      if (EcAlarmSeverityCleared == perceivedSeverity)
	{
	  /* We don't need a proposed repair action for a clear.
	   */
	  proposedRepairAction = @"";
	}
      else
	{
	  [self release];
	  [NSException raise: NSInvalidArgumentException
		      format: @"empty proposed repair action"];
	}
    }
  if (255 < strlen([proposedRepairAction UTF8String]))
    {
      [self release];
      [NSException raise: NSInvalidArgumentException
	format: @"proposed repair action too long (over 255 bytes): (%@)",
	proposedRepairAction];
    }
  if (nil == eventDate)
    {
      eventDate = [NSDate date];
    }
  if (nil == additionalText)
    {
      additionalText = @"";
    }
  if (255 < strlen([additionalText UTF8String]))
    {
      [self release];
      [NSException raise: NSInvalidArgumentException
	format: @"additional text too long (over 255 bytes): (%@)",
	additionalText];
    }
  if (nil == [c stringFromEventType: eventType])
    {
      [self release];
      [NSException raise: NSInvalidArgumentException
		  format: @"bad event type (%d)", eventType];
    }
  if (nil == [c stringFromSeverity: perceivedSeverity])
    {
      [self release];
      [NSException raise: NSInvalidArgumentException
		  format: @"bad severity (%d)", perceivedSeverity];
    }
  if (nil == [c stringFromProbableCause: probableCause])
    {
      [self release];
      [NSException raise: NSInvalidArgumentException
		  format: @"bad severity (%d)", probableCause];
    }
  /* Anything other than an unknown probable cause must correspond to a
   * known event type, but an unknown probable cause may match any event.
   */
  if (EcAlarmProbableCauseUnknown != probableCause)
    {
      _eventType = [c eventTypeFromProbableCause: probableCause];
      if (_eventType != eventType)
	{
	  [self release];
	  [NSException raise: NSInvalidArgumentException
		      format: @"missmatch of event type and probable cause"];
	}
    }

  if (nil != (self = [super init]))
    {
      _notificationID = 0;
      _eventType = eventType;
      _perceivedSeverity = perceivedSeverity;
      _probableCause = probableCause;
      _trendIndicator = 0;
      ASSIGNCOPY(_managedObject, managedObject);
      ASSIGNCOPY(_eventDate, eventDate);
      ASSIGNCOPY(_specificProblem, specificProblem);
      ASSIGNCOPY(_proposedRepairAction, proposedRepairAction);
      ASSIGNCOPY(_additionalText, additionalText);
    }
  return self;
}

- (id) initWithCoder: (NSCoder*)aCoder
{
  [aCoder decodeValuesOfObjCTypes: "iiiii@@@@@@",
    &_eventType,
    &_notificationID,
    &_perceivedSeverity,
    &_probableCause,
    &_trendIndicator,
    &_managedObject,
    &_eventDate,
    &_firstEventDate,
    &_specificProblem,
    &_proposedRepairAction,
    &_additionalText];
  return self;
}

/* Return YES if the two instances are equal according to the correlation
 * rules, NO otherwise.
 */
- (BOOL) isEqual: (id)other
{
  if (other == self)
    {
      return YES;
    }
  if (NO == [other isKindOfClass: [EcAlarm class]])
    {
      return NO;
    }
  if (NO == [[other managedObject] isEqual: _managedObject])
    {
      return NO;
    }
  if (_notificationID > 0 && [other notificationID] == _notificationID)
    {
      /* We have a notificationID set ... if both have the same notification
       * ID then they are the same.
       */
      return YES;
    }

  /* The correlation rule normally is:
   * Same managed object
   * same event type
   * same probable cause
   * same specific problem
   */
  if ([other eventType] == _eventType
    && [other probableCause] == _probableCause
    && [[other specificProblem] isEqual: _specificProblem])
    {
      return YES;
    }
  return NO;
}

- (NSString*) managedObject
{
  return _managedObject;
}

- (NSString*) moComponent
{
  NSArray	*s = [_managedObject componentsSeparatedByString: @"_"];

  return [s objectAtIndex: 3];
}

- (NSString*) moHost
{
  NSArray	*s = [_managedObject componentsSeparatedByString: @"_"];

  return [s objectAtIndex: 0];
}

- (NSString*) moInstance
{
  NSArray	*s = [_managedObject componentsSeparatedByString: @"_"];

  return [s objectAtIndex: 2];
}

- (NSString*) moProcess
{
  NSArray	*s = [_managedObject componentsSeparatedByString: @"_"];

  return [s objectAtIndex: 1];
}

- (int) notificationID
{
  return _notificationID;
}

- (EcAlarmSeverity) perceivedSeverity
{
  return _perceivedSeverity;
}

- (NSString*) proposedRepairAction
{
  return _proposedRepairAction;
}

- (EcAlarmProbableCause) probableCause
{
   return _probableCause;
}

- (id) replacementObjectForPortCoder: (NSPortCoder*)aCoder
{
  return self;
}

- (void) setExtra: (void*)extra
{
  if (YES == _frozen)
    {
      [NSException raise: NSInternalInconsistencyException
		  format: @"[%@-%@] called for frozen instance",
	NSStringFromClass([self class]), NSStringFromSelector(_cmd)];
    }
  _extra = extra;
}

- (void) setFirstEventDate: (NSDate*)firstEventDate
{
  if (nil != firstEventDate
    && NO == [firstEventDate isKindOfClass: [NSDate class]])
    {
      [NSException raise: NSInvalidArgumentException
		  format: @"[%@-%@] bad argument '%@'",
	NSStringFromClass([self class]), NSStringFromSelector(_cmd),
	firstEventDate];
    }
  if (YES == _frozen)
    {
      [NSException raise: NSInternalInconsistencyException
		  format: @"[%@-%@] called for frozen instance",
	NSStringFromClass([self class]), NSStringFromSelector(_cmd)];
    }
  ASSIGNCOPY(_firstEventDate, firstEventDate);
}

- (void) setNotificationID: (int)notificationID
{
  if (YES == _frozen)
    {
      [NSException raise: NSInternalInconsistencyException
		  format: @"[%@-%@] called for frozen instance",
	NSStringFromClass([self class]), NSStringFromSelector(_cmd)];
    }
  _notificationID = notificationID;
}

- (void) setTrendIndicator: (EcAlarmTrend)trendIndicator
{
  if (nil == [[self class] stringFromTrend: trendIndicator])
    {
      [NSException raise: NSInvalidArgumentException
		  format: @"[%@-%@] bad argument '%d'",
	NSStringFromClass([self class]), NSStringFromSelector(_cmd),
	trendIndicator];
    }
  if (YES == _frozen)
    {
      [NSException raise: NSInternalInconsistencyException
		  format: @"[%@-%@] called for frozen instance",
	NSStringFromClass([self class]), NSStringFromSelector(_cmd)];
    }
  _trendIndicator = trendIndicator;
}

- (NSString*) specificProblem
{
  return _specificProblem;
}

- (EcAlarmTrend) trendIndicator
{
  return _trendIndicator;
}

@end


@implementation	EcAlarm (Convenience)

+ (EcAlarm*) clear: (NSString*)componentName
	     cause: (EcAlarmProbableCause)probableCause
	   problem: (NSString*)specificProblem
{
  NSString		*managedObject;
  EcAlarmEventType	eventType;

  managedObject = EcMakeManagedObject(nil, nil, componentName);
  eventType = [self eventTypeFromProbableCause: probableCause];
  return [self alarmForManagedObject: managedObject
				  at: nil
		       withEventType: eventType
		       probableCause: probableCause
		     specificProblem: specificProblem
		   perceivedSeverity: EcAlarmSeverityCleared
		proposedRepairAction: nil
		      additionalText: nil];
}
		
+ (EcAlarm*) raise: (NSString*)componentName
	     cause: (EcAlarmProbableCause)probableCause
	   problem: (NSString*)specificProblem
	  severity: (EcAlarmSeverity)perceivedSeverity
	    action: (NSString*)proposedRepairAction,...
{
  NSString		*managedObject;
  EcAlarmEventType	eventType;
  NSString		*mesg;
  va_list 		ap;

  NSAssert(EcAlarmSeverityCleared != perceivedSeverity,
    NSInvalidArgumentException);

  managedObject = EcMakeManagedObject(nil, nil, componentName);
  eventType = [self eventTypeFromProbableCause: probableCause];

  va_start (ap, proposedRepairAction);
  mesg = [NSString stringWithFormat: proposedRepairAction arguments: ap];
  va_end (ap);
  return [self alarmForManagedObject: managedObject
				  at: nil
		       withEventType: eventType
		       probableCause: probableCause
		     specificProblem: specificProblem
		   perceivedSeverity: perceivedSeverity
		proposedRepairAction: mesg
		      additionalText: nil];
}

@end

