/ui-ux-pro-max Use ui-ux-pro-max to create a web page in Svelte, save it in ChenWeb/web/src/routes/home2.

# Theme

The theme of this page is "My AI Assistant". It serves as the home or main page, mainly used in users' daily work.
The page should be modern, leaning toward techies.

# Design Guidelines

- Since this is the most important page of my system, it will be too difficult to get it right on the first shot. Extracting certain design decisions as easy-to-adjust variables to make the page easy to customize is a very important design decision. Apply this design principle wisely!
- Since this is the first page my customers will see, visual appealing is very important.  But also note that this is not a web page for marketing and sales. It is for daily work.  Ensure easy-to-use and work efficiency are equally important.
- In the implementation, use variables for the visual attributes, such as page background, card surface, Secondary surface, border, divider, etc. Put these variables on the top of the .svelte file. Add a brief comment about the purpose of each variable, so that it is easy for developers to adjust the visual effects.



# Page Layout

## Top Panel
- The top panel contains a logo, a large image that contains ingredients of AI, new techs, furistic and inspiring.
- Do not use .gif images.
- The top panel height can be set to 200px). Use a variable for it so that developers can adjust it if they want to

## Left Panel
The left panel is a multi-level menu systems. Intermediate levels can be expanded or closed.
Each menu item has an icon and a name. The top level menu items should include:
- Dashboard
- Agents
- Skills
- Applications
- Coding Assistant
- Personal Assistant
- Knowledge Base
- Settings (near the bottom)
- About (near the bottom)

The bottom of the left panel shows an icon for the logged user, user name and email. There is a button with a label of three-dots. Clicking the button should pop a sub-menu that contains the User Info, Account and Log Out menu items.

## Middle Panel
- The middle panel shows the content of the menu item being selected. 
- If no item is selected, it shows the dashboard. 
- The middle panel height should be elastic, determined by its content.

## Right Panel
The right panel shows additional information about the selected menu item.

## Adjustable Left and Right Panel
The left and right panel widths are adjustable by sliding on a divider. On hover each divider highlights
the divider and shows four grab dots.

## Bottom Panel
- The bottom panel serves as the footer. Make sure you create a rich footer for me.
- The bottom panel floats on (i.e., attaches to) the middle panel, with a big enough gap.

## Development Requirements
- Frontend is Svelte (ChenWeb/web). 
- Backend is Go (ChenWeb/server).

## Style
- Support two modes: light and dark
- The majority colors are light and dark
- Use Shdcn components if available
- light grey base (not white), with a strong accent color for interactive elements. Feels closer to
  Notion or Craft — calm and focused, easy on the eyes during long sessions.
- Light and dark mode both look equally refined.
- 'dark' should not be pure black

# REST API and Backend
- Create all the needed REST API endpoints
- Create all the handlers with stubs only