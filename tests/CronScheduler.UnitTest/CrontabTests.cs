using System;
using System.Diagnostics;
using System.Globalization;
using System.Threading;
using CronScheduler.AspNetCore.Cron;
using Xunit;

namespace CronScheduler.UnitTest
{
    public class CrontabTests
    {
        const string TimeFormat = "dd/MM/yyyy HH:mm:ss";

        [Fact]
        public void Cannot_Parse_Null_String()
        {
            Assert.Throws<ArgumentNullException>(() =>  CrontabSchedule.Parse(null));
        }

        [Fact]
        public void Cannot_Parse_Empty_String()
        {
            Assert.Throws<FormatException>(() => CrontabSchedule.Parse(string.Empty));
        }

        [Fact]

        public void All_Time_String()
        {
            Assert.Equal("* * * * *", CrontabSchedule.Parse("* * * * *").ToString());
        }

        [Fact]
        public void Formatting()
        {
            Assert.Equal("* 1-3 * * *", CrontabSchedule.Parse("* 1-2,3 * * *").ToString());
            Assert.Equal("* * * 1,3,5,7,9,11 *", CrontabSchedule.Parse("* * * */2 *").ToString());
            Assert.Equal("10,25,40 * * * *", CrontabSchedule.Parse("10-40/15 * * * *").ToString());
            Assert.Equal("* * * 1,3,8 1-2,5", CrontabSchedule.Parse("* * * Mar,Jan,Aug Fri,Mon-Tue").ToString());
        }

        [Fact]
        public void Eval_All_Time()
        {
            CronCall("01/01/2003 00:00:00", "* * * * *", "01/01/2003 00:01:00");
            CronCall("01/01/2003 00:01:00", "* * * * *", "01/01/2003 00:02:00");
            CronCall("01/01/2003 00:02:00", "* * * * *", "01/01/2003 00:03:00");
            CronCall("01/01/2003 00:59:00", "* * * * *", "01/01/2003 01:00:00");
            CronCall("01/01/2003 01:59:00", "* * * * *", "01/01/2003 02:00:00");
            CronCall("01/01/2003 23:59:00", "* * * * *", "02/01/2003 00:00:00");
            CronCall("31/12/2003 23:59:00", "* * * * *", "01/01/2004 00:00:00");

            CronCall("28/02/2003 23:59:00", "* * * * *", "01/03/2003 00:00:00");
            CronCall("28/02/2004 23:59:00", "* * * * *", "29/02/2004 00:00:00");
        }

        [Fact]
        public void Eval_Minute_Time()
        {
            CronCall("01/01/2003 00:00:00", "45 * * * *", "01/01/2003 00:45:00");

            CronCall("01/01/2003 00:00:00", "45-47,48,49 * * * *", "01/01/2003 00:45:00");
            CronCall("01/01/2003 00:45:00", "45-47,48,49 * * * *", "01/01/2003 00:46:00");
            CronCall("01/01/2003 00:46:00", "45-47,48,49 * * * *", "01/01/2003 00:47:00");
            CronCall("01/01/2003 00:47:00", "45-47,48,49 * * * *", "01/01/2003 00:48:00");
            CronCall("01/01/2003 00:48:00", "45-47,48,49 * * * *", "01/01/2003 00:49:00");
            CronCall("01/01/2003 00:49:00", "45-47,48,49 * * * *", "01/01/2003 01:45:00");

            CronCall("01/01/2003 00:00:00", "2/5 * * * *", "01/01/2003 00:02:00");
            CronCall("01/01/2003 00:02:00", "2/5 * * * *", "01/01/2003 00:07:00");
            CronCall("01/01/2003 00:50:00", "2/5 * * * *", "01/01/2003 00:52:00");
            CronCall("01/01/2003 00:52:00", "2/5 * * * *", "01/01/2003 00:57:00");
            CronCall("01/01/2003 00:57:00", "2/5 * * * *", "01/01/2003 01:02:00");

        }

        [Fact]
        public void Eval_Hour_Time()
        {
            CronCall("20/12/2003 10:00:00", " * 3/4 * * *", "20/12/2003 11:00:00");
            CronCall("20/12/2003 00:30:00", " * 3   * * *", "20/12/2003 03:00:00");
            CronCall("20/12/2003 01:45:00", "30 3   * * *", "20/12/2003 03:30:00");
        }

        [Fact]
        public void Eval_DayOfMonth_Time()
        {
            CronCall("07/01/2003 00:00:00", "30  *  1 * *", "01/02/2003 00:30:00");
            CronCall("01/02/2003 00:30:00", "30  *  1 * *", "01/02/2003 01:30:00");

            CronCall("01/01/2003 00:00:00", "10  * 22    * *", "22/01/2003 00:10:00");
            CronCall("01/01/2003 00:00:00", "30 23 19    * *", "19/01/2003 23:30:00");
            CronCall("01/01/2003 00:00:00", "30 23 21    * *", "21/01/2003 23:30:00");
            CronCall("01/01/2003 00:01:00", " *  * 21    * *", "21/01/2003 00:00:00");
            CronCall("10/07/2003 00:00:00", " *  * 30,31 * *", "30/07/2003 00:00:00");

        }

        [Fact]
        public void Eval_Month_Time()
        {
            // Test month rollovers for months with 28,29,30 and 31 days
            CronCall("28/02/2002 23:59:59", "* * * 3 *", "01/03/2002 00:00:00");
            CronCall("29/02/2004 23:59:59", "* * * 3 *", "01/03/2004 00:00:00");
            CronCall("31/03/2002 23:59:59", "* * * 4 *", "01/04/2002 00:00:00");
            CronCall("30/04/2002 23:59:59", "* * * 5 *", "01/05/2002 00:00:00");
            // Test month 30,31 days
            CronCall("01/01/2000 00:00:00", "0 0 15,30,31 * *", "15/01/2000 00:00:00");
            CronCall("15/01/2000 00:00:00", "0 0 15,30,31 * *", "30/01/2000 00:00:00");
            CronCall("30/01/2000 00:00:00", "0 0 15,30,31 * *", "31/01/2000 00:00:00");
            CronCall("31/01/2000 00:00:00", "0 0 15,30,31 * *", "15/02/2000 00:00:00");
            CronCall("15/02/2000 00:00:00", "0 0 15,30,31 * *", "15/03/2000 00:00:00");
            CronCall("15/03/2000 00:00:00", "0 0 15,30,31 * *", "30/03/2000 00:00:00");
            CronCall("30/03/2000 00:00:00", "0 0 15,30,31 * *", "31/03/2000 00:00:00");
            CronCall("31/03/2000 00:00:00", "0 0 15,30,31 * *", "15/04/2000 00:00:00");
            CronCall("15/04/2000 00:00:00", "0 0 15,30,31 * *", "30/04/2000 00:00:00");
            CronCall("30/04/2000 00:00:00", "0 0 15,30,31 * *", "15/05/2000 00:00:00");
            CronCall("15/05/2000 00:00:00", "0 0 15,30,31 * *", "30/05/2000 00:00:00");
            CronCall("30/05/2000 00:00:00", "0 0 15,30,31 * *", "31/05/2000 00:00:00");
            CronCall("31/05/2000 00:00:00", "0 0 15,30,31 * *", "15/06/2000 00:00:00");
            CronCall("15/06/2000 00:00:00", "0 0 15,30,31 * *", "30/06/2000 00:00:00");
            CronCall("30/06/2000 00:00:00", "0 0 15,30,31 * *", "15/07/2000 00:00:00");
            CronCall("15/07/2000 00:00:00", "0 0 15,30,31 * *", "30/07/2000 00:00:00");
            CronCall("30/07/2000 00:00:00", "0 0 15,30,31 * *", "31/07/2000 00:00:00");
            CronCall("31/07/2000 00:00:00", "0 0 15,30,31 * *", "15/08/2000 00:00:00");
            CronCall("15/08/2000 00:00:00", "0 0 15,30,31 * *", "30/08/2000 00:00:00");
            CronCall("30/08/2000 00:00:00", "0 0 15,30,31 * *", "31/08/2000 00:00:00");
            CronCall("31/08/2000 00:00:00", "0 0 15,30,31 * *", "15/09/2000 00:00:00");
            CronCall("15/09/2000 00:00:00", "0 0 15,30,31 * *", "30/09/2000 00:00:00");
            CronCall("30/09/2000 00:00:00", "0 0 15,30,31 * *", "15/10/2000 00:00:00");
            CronCall("15/10/2000 00:00:00", "0 0 15,30,31 * *", "30/10/2000 00:00:00");
            CronCall("30/10/2000 00:00:00", "0 0 15,30,31 * *", "31/10/2000 00:00:00");
            CronCall("31/10/2000 00:00:00", "0 0 15,30,31 * *", "15/11/2000 00:00:00");
            CronCall("15/11/2000 00:00:00", "0 0 15,30,31 * *", "30/11/2000 00:00:00");
            CronCall("30/11/2000 00:00:00", "0 0 15,30,31 * *", "15/12/2000 00:00:00");
            CronCall("15/12/2000 00:00:00", "0 0 15,30,31 * *", "30/12/2000 00:00:00");
            CronCall("30/12/2000 00:00:00", "0 0 15,30,31 * *", "31/12/2000 00:00:00");
            CronCall("31/12/2000 00:00:00", "0 0 15,30,31 * *", "15/01/2001 00:00:00");

            // Other month tests (including year rollover)

            CronCall("01/12/2003 05:00:00", "10 * * 6 *", "01/06/2004 00:10:00");
            CronCall("04/01/2003 00:00:00", " 1 2 3 * *", "03/02/2003 02:01:00");
            CronCall("01/07/2002 05:00:00", "10 * * February,April-Jun *", "01/02/2003 00:10:00");
            CronCall("01/01/2003 00:00:00", "0 12 1 6 *", "01/06/2003 12:00:00");
            CronCall("11/09/1988 14:23:00", "* 12 1 6 *", "01/06/1989 12:00:00");
            CronCall("11/03/1988 14:23:00", "* 12 1 6 *", "01/06/1988 12:00:00");
            CronCall("11/03/1988 14:23:00", "* 2,4-8,15 * 6 *", "01/06/1988 02:00:00");
            CronCall("11/03/1988 14:23:00", "20 * * january,FeB,Mar,april,May,JuNE,July,Augu,SEPT-October,Nov,DECEM *", "11/03/1988 15:20:00");
        }

        [Fact]
        public void Eval_Week_Time()
        {
            // Day of week tests

            CronCall("26/06/2003 10:00:00", "30 6 * * 0", "29/06/2003 06:30:00");
            CronCall("26/06/2003 10:00:00", "30 6 * * sunday", "29/06/2003 06:30:00");
            CronCall("26/06/2003 10:00:00", "30 6 * * SUNDAY", "29/06/2003 06:30:00");
            CronCall("19/06/2003 00:00:00", "1 12 * * 2", "24/06/2003 12:01:00");
            CronCall("24/06/2003 12:01:00", "1 12 * * 2", "01/07/2003 12:01:00");

            CronCall("01/06/2003 14:55:00", "15 18 * * Mon", "02/06/2003 18:15:00");
            CronCall("02/06/2003 18:15:00", "15 18 * * Mon", "09/06/2003 18:15:00");
            CronCall("09/06/2003 18:15:00", "15 18 * * Mon", "16/06/2003 18:15:00");
            CronCall("16/06/2003 18:15:00", "15 18 * * Mon", "23/06/2003 18:15:00");
            CronCall("23/06/2003 18:15:00", "15 18 * * Mon", "30/06/2003 18:15:00");
            CronCall("30/06/2003 18:15:00", "15 18 * * Mon", "07/07/2003 18:15:00");

            CronCall("01/01/2003 00:00:00", "* * * * Mon", "06/01/2003 00:00:00");
            CronCall("01/01/2003 12:00:00", "45 16 1 * Mon", "01/09/2003 16:45:00");
            CronCall("01/09/2003 23:45:00", "45 16 1 * Mon", "01/12/2003 16:45:00");
        }

        [Fact]
        public void Eval_Year_Time()
        {
            // Leap year tests

            CronCall("01/01/2000 12:00:00", "1 12 29 2 *", "29/02/2000 12:01:00");
            CronCall("29/02/2000 12:01:00", "1 12 29 2 *", "29/02/2004 12:01:00");
            CronCall("29/02/2004 12:01:00", "1 12 29 2 *", "29/02/2008 12:01:00");

            // Non-leap year tests

            CronCall("01/01/2000 12:00:00", "1 12 28 2 *", "28/02/2000 12:01:00");
            CronCall("28/02/2000 12:01:00", "1 12 28 2 *", "28/02/2001 12:01:00");
            CronCall("28/02/2001 12:01:00", "1 12 28 2 *", "28/02/2002 12:01:00");
            CronCall("28/02/2002 12:01:00", "1 12 28 2 *", "28/02/2003 12:01:00");
            CronCall("28/02/2003 12:01:00", "1 12 28 2 *", "28/02/2004 12:01:00");
            CronCall("29/02/2004 12:01:00", "1 12 28 2 *", "28/02/2005 12:01:00");
        }

        [Fact]
        public void FiniteOccurrences()
        {
            CronFinite(" *  * * * *  ", "01/01/2003 00:00:00", "01/01/2003 00:00:00");
            CronFinite(" *  * * * *  ", "31/12/2002 23:59:59", "01/01/2003 00:00:00");
            CronFinite(" *  * * * Mon", "31/12/2002 23:59:59", "01/01/2003 00:00:00");
            CronFinite(" *  * * * Mon", "01/01/2003 00:00:00", "02/01/2003 00:00:00");
            CronFinite(" *  * * * Mon", "01/01/2003 00:00:00", "02/01/2003 12:00:00");
            CronFinite("30 12 * * Mon", "01/01/2003 00:00:00", "06/01/2003 12:00:00");
        }

        [Fact]
        public void Dont_Loop_Indefinitely()
        {
            //
            // Test to check we don't loop indefinitely looking for a February
            // 31st because no such date would ever exist!
            //

            TimeCron(TimeSpan.FromSeconds(1), () =>
                CronFinite("* * 31 Feb *", "01/01/2001 00:00:00", "01/01/2010 00:00:00"));
           }

        [Fact]
        public void Bad_Minutes_Field()
        {
            Assert.Throws<FormatException>(() => CrontabSchedule.Parse("bad * * * *"));
        }

        [Fact]
        public void Bad_Hours_Field()
        {
            Assert.Throws<FormatException>(() => CrontabSchedule.Parse("* bad * * *"));
        }

        [Fact]
        public void Bad_Seconds_Field()
        {
            Assert.Throws<FormatException>(()=> CrontabSchedule.Parse("bad * * * * *"));
        }

        [Fact]
        public void Bad_Day_Field()
        {
            Assert.Throws<FormatException>(() => CrontabSchedule.Parse("* * bad * *"));
        }

        [Fact]
        public void Bad_Month_Field()
        {
            Assert.Throws<FormatException>(() => CrontabSchedule.Parse("* * * bad *"));
        }

        [Fact]
        public void Bad_DayOfWeek_Field()
        {
            Assert.Throws<FormatException>(() => CrontabSchedule.Parse("* * * * mon,bad,wed"));
        }

        [Fact]
        public void OutOfRange_Field()
        {
            Assert.Throws<FormatException>(() => CrontabSchedule.Parse("* 1,2,3,456,7,8,9 * * *"));
        }

        [Fact]
        public void Non_Number_Value_In_Numeric_Only_Field()
        {
            Assert.Throws<FormatException>(() => CrontabSchedule.Parse("* 1,Z,3,4 * * *"));
        }

        [Fact]
        public void Non_Numeric_Field_Interval()
        {
            Assert.Throws<FormatException>(() => CrontabSchedule.Parse("* 1/Z * * *"));
        }

        [Fact]
        public void Non_Numeric_Field_Range_Component()
        {
            Assert.Throws<FormatException>(() => CrontabSchedule.Parse("* 3-l2 * * *"));
            Assert.Throws<FormatException>(() => CrontabSchedule.Parse("* * 3-l2 * * *"));
        }

        private static void TimeCron(TimeSpan limit, ThreadStart test)
        {
            Debug.Assert(test != null);
            Exception e = null;
            var worker = new Thread(() => { try { test(); } catch (Exception ee) { e = ee; } });
            worker.Start();
            if (worker.Join(!Debugger.IsAttached ? (int)limit.TotalMilliseconds : Timeout.Infinite))
            {
                if (e != null)
                    throw new Exception(e.Message, e);
                return;
            }
            worker.Abort();
            Assert.True(false,$"The test did not complete in the allocated time ({limit}). " +
                        "Check there is not an infinite loop somewhere.");
        }

        #region CrontFinite
        private delegate void CronFiniteHandler(string cronExpression, string startTimeString, string endTimeString);
        private void CronFinite(string cronExpression, string startTimeString, string endTimeString)
        {
            CronFinite()(cronExpression, startTimeString, endTimeString);
        }
        private static CronFiniteHandler CronFinite()
        {
            return (cronExpression, startTimeString, endTimeString) =>
            {
                var schedule = CrontabSchedule.Parse(cronExpression);
                var occurrence = schedule.GetNextOccurrence(Time(startTimeString), Time(endTimeString));

                Assert.Equal(endTimeString, TimeString(occurrence));
            };
        }
        #endregion

        #region CronCallHandler
        private delegate void CronCallHandler(string startTimeString, string cronExpression, string nextTimeString);
        private static void CronCall(string startTimeString, string cronExpression, string nextTimeString)
        {
            CronCall()(startTimeString, cronExpression, nextTimeString);
        }
        private static CronCallHandler CronCall()
        {
            return (startTimeString, cronExpression, nextTimeString) =>
            {
                var start = Time(startTimeString);

                try
                {
                    var schedule = CrontabSchedule.Parse(cronExpression);

                    var next = schedule.GetNextOccurrence(start);

                    Assert.Equal(nextTimeString, TimeString(next));
                }
                catch (FormatException e)
                {
                    Assert.True(false, $"Unexpected ParseException while parsing <{cronExpression}>: {e.ToString()}");
                }
            };
        }
        #endregion

        private static DateTime Time(string str)
        {
            return DateTime.ParseExact(str, TimeFormat, CultureInfo.InvariantCulture);
        }

        private static string TimeString(DateTime time)
        {
            return time.ToString(TimeFormat, CultureInfo.InvariantCulture);
        }

    }
}
