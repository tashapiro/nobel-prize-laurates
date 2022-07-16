#for data scraping
library(httr)
library(jsonlite)
library(rvest)
#for plotting
library(tidyverse)
library(ggiraph)
library(ggtext)
#for fonts
library(sysfonts)
library(showtext)
#for saving plot as HTML
library(htmlwidgets)


#set font for later (uses sysfonts and showtext)
font_add_google("jost", "jost")
showtext_auto()

#get laureate data with nobel prize API
res1 = GET('http://api.nobelprize.org/2.1/laureates?limit=1000')
json_laureate = fromJSON(rawToChar(res1$content))

laureate <- json_laureate$laureates

#create data of noble laureates
df_laureate<-laureate%>%
  unnest(c(fullName, givenName, familyName, birth, wikipedia),  names_repair = tidyr_legacy)%>%
  select(id, en, en1, en2, gender, date, place, english)%>%
  rename(id="id",
         last_name = "en",
         first_name = "en1",
         full_name = "en2",
         birth_date = "date",
         wikipedia = "english")%>%
  unnest(place)%>%
  unnest(cityNow, countryNow, names_repair = tidyr_legacy)%>%
  select(id, full_name, first_name, last_name, birth_date, gender, en, en1, wikipedia)%>%
  rename(birth_city = "en",
         birth_country = "en1")


#create data set of awards (noble prizes)
df_prize<-laureate%>%
  select(id, nobelPrizes)%>%
  unnest(nobelPrizes, repair="universal")%>%
  select(id, awardYear, category, motivation)%>%
  unnest(category, motivation)%>%
  select(id, awardYear, en, en1)%>%
  rename(laureate_id="id",award_year="awardYear",category="en", motivation="en1")

#combine the two datasets
df_prize_laureate<-left_join(df_prize, df_laureate, by=c("laureate_id"="id"))
#convert year to integer
df_prize_laureate$award_year<-as.integer(df_prize_laureate$award_year)
#dummy counter used for future aggregateions
df_prize_laureate$count <- 1

#function to scrape image urls for laureates, 
get_image<-function(url){
  #get images
  images=url|>
    read_html()|>
    html_elements("picture")|>
    html_elements("source")|>
    html_attr("data-srcset")
  #remove misc images that aren't laureates
  mini_images=images[grepl("portrait-mini", images)]
  #concatenate as html image tags
  image_tags=paste0('<img src="',mini_images,'" width=120>')
  #image_tags
  paste(image_tags, collapse=" ")
}


#get image links for all laureates - this part will take some time with lapply get image function!
df_pl_img<-df_prize_laureate%>%
  mutate(noble_link = case_when(
    category=="Physiology or Medicine"~paste("https://www.nobelprize.org/prizes/medicine/",award_year,"/summary/",sep=""),
    category=="Economic Sciences"~paste("https://www.nobelprize.org/prizes/economic-sciences/",award_year,"/summary/",sep=""),
    TRUE~paste("https://www.nobelprize.org/prizes/",tolower(category),"/",award_year,"/summary/",sep="")
  ),
  images = lapply(noble_link, get_image))



#reshape data
df_grouping<-df_pl_img%>%
  #fill in years for all categories to help render tile graph (otherwise will not plot tile!)
  complete(category= unique(df_prize_laureate$category), award_year=1901:2021)%>%
  #mutate to help wrap text for "motivation"
  mutate(motivation = gsub("(\\S* \\S* \\S* \\S* \\S* \\S* \\S* \\S*)","\\1<br>", motivation))%>%
  #aggregation to group information by year and category 
  group_by(category,award_year, images, noble_link)%>%
  summarise(total_count=sum(count),
            male_count = sum(count[gender=="male"]),
            female_count = sum(count[gender=="female"]),
            recipients = paste(full_name, collapse=" <br> "),
            motivation = paste(unique(motivation), collapse=" <br> "))%>%
  rename(img_link = images)%>%
  mutate(
    grouping=case_when(
      female_count == total_count ~ "Female",
      male_count == total_count ~ "Male",
      female_count>0 ~"Mixed Team",
      motivation!="NA" ~ "Organization",
      TRUE ~ "No Award"),
    grouping=factor(grouping, levels=c("Female","Male","Mixed Team","Organization","No Award")),
    category = factor(category, levels=c("Economic Sciences","Peace","Literature","Chemistry","Physics","Physiology or Medicine")),
    award_decade= round(award_year / 10) * 10,
    year_split = case_when(
      award_year>=1981 ~"1981-2021",
      award_year>=1941 ~"1941-1980",
      award_year>=1901~"1901-1940"
    ),
    tooltip = case_when(motivation!="NA"~
      paste("<center><b>",category," (",toupper(award_year),")</b> <br><br>",img_link,"<br>",
            recipients,"</br></center>","<br>","<center><b>Motivation</b></center>",motivation, sep=""),
      motivation=="NA" & category=="Economic Sciences" & award_year<1969 ~paste("<b>",category," (",award_year,")</b> <br> Nobel Memorial Prize in Economic Sciences <br> not introduced until 1969"),
      TRUE ~  paste("<b>",category," (",award_year,")</b> <br> No Nobel Prize awarded this year"))
  )




#aeshtetics
pal<-c("#FFC56F","#755638","#BD904C","#3B342B","grey85")

#tooltip add ons
#unique id needed to identify distinct objects for hover
df_grouping$id<-paste(df_grouping$award_year,df_grouping$category)
#onclick used for tooltip click actions - open window using the nobel link for year/category
df_grouping$onclick <- sprintf("window.open(\"%s\")",df_grouping$noble_link)

#store ggplot graphic into object
graph<- ggplot(df_grouping, aes(x=award_year,y=category,fill=grouping))+
  geom_tile_interactive(aes(tooltip=tooltip, data_id=id, onclick=onclick),colour="white", width=.9, height=.9)+
  scale_fill_manual(values=pal,
                    guide = guide_legend_interactive(
                      override.aes=list(size=3),
                      title.position="top",
                      title.hjust=0.5,
                      title.theme = element_text_interactive(
                        size = 8,
                        family="jost"
                      ),
                      label.theme = element_text_interactive(
                        size = 8,
                        family="jost"
                      )))+
  facet_wrap(~year_split, ncol=1, scales="free_x")+
  theme_void()+
  theme(
    text=element_text(family="jost"),
    legend.position = "top",
    legend.title=element_blank(),
    legend.text=element_text(size=8),
    legend.key.size = unit(0.4, 'cm'),
    plot.title=element_text(hjust=0.5, size=17, vjust=5, color="#9A783E"),
    plot.subtitle=element_markdown(hjust=0.5, color="grey50", vjust=8, size=8, margin=margin(b=7)),
  #  axis.title.x = element_text(family="Gill Sans"),
    legend.box.margin = margin(b=7),
    axis.text = element_text(size=6),
    axis.text.y = element_text(hjust = 1, size=6),
    strip.text.x = element_text(size = 8, vjust=0.5),
    plot.caption = element_text(size=5, hjust=0.95, margin=margin(t=15)),
    plot.margin= margin(r=70, t=15, l=10)
  )+
  labs(caption="Data from Nobel Prize API | Chart @tanya_shapiro",
       subtitle='The Nobel Prize is awareded to those "who have conferred the greatest benefit to Humankind. Recipients are referred to as " <br> 
       laureates. There are five categories, a sixth category, the Nobel Memorial Prize in Economic Sciences, was introduced in 1969. <br>
       Prizes can be awarded to individuals, organizations, or teams. **Mixed Team** denotes a team with male & female laureates.',
       x="Year",
       y="Category",
       title="NOBEL PRIZE LAUREATES", fill="")


#store csss for tooltip
tooltip_css <- "background-color:black;color:white;font-family:sans-serif;padding:10px;border-radius:5px;"

#create interactive plot using ggiraph
interactive<-girafe(ggobj=graph,  
          options = list(opts_tooltip(css = tooltip_css),
                         opts_hover(css = "fill:#AFE1AF;cursor:pointer;")),
          width_svg=9, height_svg=5.25)

#preview interactive plot
interactive

#save plot as HTML file
saveWidget(interactive, "nobel-square.html", selfcontained = T)

